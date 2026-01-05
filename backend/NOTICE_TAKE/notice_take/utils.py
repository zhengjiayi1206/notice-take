from typing import Optional


def mask_token(token: Optional[str]) -> Optional[str]:
    if not token:
        return token
    return f"***{token[-8:]}" if len(token) > 8 else "***"


def guess_mime(filename: str, content_type: Optional[str]) -> str:
    if content_type:
        return content_type
    fn = (filename or "").lower()
    if fn.endswith(".wav"):
        return "audio/wav"
    if fn.endswith(".mp3"):
        return "audio/mpeg"
    if fn.endswith(".m4a"):
        return "audio/mp4"
    if fn.endswith(".aac"):
        return "audio/aac"
    if fn.endswith(".ogg"):
        return "audio/ogg"
    return "application/octet-stream"


def extract_json(text: Optional[str]) -> Optional[str]:
    if not text:
        return None
    start = text.find("[")
    end = text.rfind("]")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return None
