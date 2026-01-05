import json
from pathlib import Path
from typing import Optional
from urllib import error as url_error
from urllib import parse as url_parse
from urllib import request as url_request


def load_hms_token_from_file(path: Path) -> Optional[str]:
    try:
        token = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    return token or None


def request_hms_access_token(client_id: str, client_secret: str) -> str:
    payload = url_parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        }
    ).encode("utf-8")
    req = url_request.Request(
        "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with url_request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8")
    except url_error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"HMS 获取 token 失败: {exc.code} {error_body}") from exc
    data = json.loads(body)
    access_token = data.get("access_token")
    if not access_token:
        raise RuntimeError(f"HMS 获取 token 失败: {body}")
    return access_token


def send_hms_push(
    access_token: str,
    app_id: str,
    token: str,
    title: str,
    body: str,
    data: Optional[dict],
    channel_id: Optional[str],
):
    url = f"https://push-api.cloud.huawei.com/v1/{app_id}/messages:send"
    message = {
        "token": [token],
        "notification": {"title": title, "body": body},
        "android": {
            "notification": {
                "title": title,
                "body": body,
                "click_action": {"type": 3},
            }
        },
    }
    if data:
        message["data"] = json.dumps(data, ensure_ascii=False)
    payload = {"validate_only": False, "message": message}
    req = url_request.Request(
        url,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "Content-Type": "application/json;charset=UTF-8",
            "Authorization": f"Bearer {access_token}",
        },
        method="POST",
    )
    try:
        with url_request.urlopen(req, timeout=10) as resp:
            body_text = resp.read().decode("utf-8")
    except url_error.HTTPError as exc:
        error_body = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"HMS 推送失败: {exc.code} {error_body}") from exc
    return json.loads(body_text)
