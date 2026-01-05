import base64
import json
from typing import Optional

import dashscope
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from openai import OpenAI
from pydantic import BaseModel, Field

from notice_take.config import (
    EVENTS_PROMPT_PATH,
    HMS_TOKEN_PATH,
    LOG_PATH,
    get_dashscope_api_key,
    get_dashscope_base_url,
    get_dashscope_compatible_base_url,
    get_environment,
    get_firebase_service_account_path,
    get_hms_app_id,
    get_hms_client_id,
    get_hms_client_secret,
)
from notice_take.logging_utils import log_event, setup_logger
from notice_take.services.firebase import get_firebase_app
from notice_take.services.hms import (
    load_hms_token_from_file,
    request_hms_access_token,
    send_hms_push,
)
from notice_take.utils import extract_json, guess_mime, mask_token
from notice_take.config import load_text
from firebase_admin import messaging

ENV = get_environment()

dashscope.base_http_api_url = get_dashscope_base_url(ENV)
API_KEY = get_dashscope_api_key(ENV)
if not API_KEY:
    raise RuntimeError("请先在 config/env.json 配置 dashscope_api_key 或设置环境变量 DASHSCOPE_API_KEY")

app = FastAPI(title="ASR Service")

OPENAI_BASE_URL = get_dashscope_compatible_base_url(ENV)
openai_client = OpenAI(
    api_key=API_KEY,
    base_url=OPENAI_BASE_URL,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logger = setup_logger(LOG_PATH)


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/asr")
async def asr_audio(
    audio: UploadFile = File(...),
    language: Optional[str] = None,
    enable_itn: bool = False,
):
    try:
        audio_bytes = await audio.read()
        if not audio_bytes:
            raise HTTPException(status_code=400, detail="音频为空")

        mime = guess_mime(audio.filename, audio.content_type)
        base64_str = base64.b64encode(audio_bytes).decode("utf-8")
        data_uri = f"data:{mime};base64,{base64_str}"

        messages = [
            {"role": "system", "content": [{"text": ""}]},
            {"role": "user", "content": [{"audio": data_uri}]},
        ]

        asr_opts = {"enable_itn": enable_itn}
        if language:
            asr_opts["language"] = language

        resp = dashscope.MultiModalConversation.call(
            api_key=API_KEY,
            model="qwen3-asr-flash",
            messages=messages,
            result_format="message",
            asr_options=asr_opts,
        )

        text = None
        try:
            content = resp.output.choices[0].message.content
            for item in content:
                if isinstance(item, dict) and "text" in item:
                    text = item["text"]
                    break
        except Exception:
            pass

        log_event(
            logger,
            "asr",
            "ok",
            {
                "filename": audio.filename,
                "content_type": mime,
                "size": len(audio_bytes),
                "language": language,
                "enable_itn": enable_itn,
            },
            {"text": text},
            None,
        )

        return {
            "text": text,
            "raw": resp,
        }

    except HTTPException as exc:
        log_event(
            logger,
            "asr",
            "error",
            {
                "filename": audio.filename if audio else None,
                "content_type": audio.content_type if audio else None,
                "language": language,
                "enable_itn": enable_itn,
            },
            None,
            str(exc.detail),
        )
        raise
    except Exception as exc:
        log_event(
            logger,
            "asr",
            "error",
            {
                "filename": audio.filename if audio else None,
                "content_type": audio.content_type if audio else None,
                "language": language,
                "enable_itn": enable_itn,
            },
            None,
            str(exc),
        )
        logger.exception("asr error=%s", exc)
        raise HTTPException(status_code=500, detail=f"ASR失败: {exc}")


class ChatRequest(BaseModel):
    content: str = Field(..., min_length=1)
    model: str = "qwen-flash"
    enable_thinking: bool = False
    current_date: str = Field(..., min_length=1)
    current_weekday: str = Field(..., min_length=1)


class EventRule(BaseModel):
    day: Optional[str] = None
    month: Optional[str] = None
    year: Optional[str] = None
    weekday: Optional[str] = None
    description: str
    note: Optional[str] = None


class EventItem(BaseModel):
    is_recurring: bool
    recurrence: Optional[str] = None
    rule: Optional[EventRule] = None
    summary: str


class PushRequest(BaseModel):
    token: str = Field(..., min_length=1)
    title: str = Field(..., min_length=1)
    body: str = Field(..., min_length=1)
    data: Optional[dict] = None


class HmsPushRequest(BaseModel):
    token: Optional[str] = None
    title: str = Field(..., min_length=1)
    body: str = Field(..., min_length=1)
    data: Optional[dict] = None
    channel_id: Optional[str] = None


@app.post("/events/parse")
def chat_text(payload: ChatRequest):
    raw_content = None
    try:
        system_prompt = load_text(EVENTS_PROMPT_PATH)
        system_prompt = (
            system_prompt.replace("<CURRENT_DATE>", payload.current_date).replace(
                "<CURRENT_WEEKDAY>", payload.current_weekday
            )
        )
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": payload.content},
        ]
        resp = openai_client.chat.completions.create(
            model=payload.model,
            messages=messages,
            extra_body={"enable_thinking": payload.enable_thinking},
        )

        choice = resp.choices[0] if resp.choices else None
        message = choice.message if choice else None
        raw_content = message.content if message else None
        json_text = extract_json(raw_content)
        if not json_text:
            log_event(
                logger,
                "events.parse",
                "ok",
                {"content": payload.content},
                {"raw": raw_content, "parsed": []},
                None,
            )
            return []
        result = json.loads(json_text)
        log_event(
            logger,
            "events.parse",
            "ok",
            {"content": payload.content},
            {"raw": raw_content, "parsed": result},
            None,
        )
        return result
    except Exception as exc:
        log_event(
            logger,
            "events.parse",
            "error",
            {"content": payload.content},
            {"raw": raw_content} if raw_content is not None else None,
            str(exc),
        )
        logger.exception("events.parse error=%s", exc)
        raise HTTPException(status_code=500, detail=f"模型调用失败: {exc}")


@app.post("/push/send")
def push_send(payload: PushRequest):
    try:
        service_account_path = get_firebase_service_account_path(ENV)
        app_instance = get_firebase_app(service_account_path)
        data = None
        if payload.data:
            data = {str(k): str(v) for k, v in payload.data.items()}
        message = messaging.Message(
            notification=messaging.Notification(
                title=payload.title,
                body=payload.body,
            ),
            data=data,
            token=payload.token,
        )
        response = messaging.send(message, app=app_instance)
        log_event(
            logger,
            "push.send",
            "ok",
            {"token": mask_token(payload.token), "title": payload.title},
            {"message_id": response},
            None,
        )
        return {"message_id": response}
    except Exception as exc:
        log_event(
            logger,
            "push.send",
            "error",
            {"token": mask_token(payload.token), "title": payload.title},
            None,
            str(exc),
        )
        logger.exception("push.send error=%s", exc)
        raise HTTPException(status_code=500, detail=f"推送失败: {exc}")


@app.post("/hms/send")
def hms_send(payload: HmsPushRequest):
    app_id = None
    client_id = None
    client_secret = None
    token = None
    try:
        token = payload.token or load_hms_token_from_file(HMS_TOKEN_PATH)
        if not token:
            raise HTTPException(status_code=400, detail="缺少 HMS token")
        app_id = get_hms_app_id(ENV)
        if not app_id:
            raise RuntimeError("未配置 HMS app_id")
        client_id = get_hms_client_id(ENV)
        client_secret = get_hms_client_secret(ENV)
        if not client_id or not client_secret:
            raise RuntimeError("未配置 HMS client_id/client_secret")
        access_token = request_hms_access_token(client_id, client_secret)
        response = send_hms_push(
            access_token,
            app_id,
            token,
            payload.title,
            payload.body,
            payload.data,
            payload.channel_id,
        )
        log_event(
            logger,
            "hms.send",
            "ok",
            {
                "token": mask_token(token),
                "title": payload.title,
                "body": payload.body,
                "data": payload.data,
                "channel_id": payload.channel_id,
                "app_id": app_id,
                "client_id": mask_token(client_id),
                "client_secret": mask_token(client_secret),
            },
            response,
            None,
        )
        return response
    except HTTPException:
        raise
    except Exception as exc:
        log_event(
            logger,
            "hms.send",
            "error",
            {
                "token": mask_token(token or payload.token),
                "title": payload.title,
                "body": payload.body,
                "data": payload.data,
                "channel_id": payload.channel_id,
                "app_id": app_id,
                "client_id": mask_token(client_id),
                "client_secret": mask_token(client_secret),
            },
            None,
            str(exc),
        )
        logger.exception("hms.send error=%s", exc)
        raise HTTPException(status_code=500, detail=f"HMS 推送失败: {exc}")
