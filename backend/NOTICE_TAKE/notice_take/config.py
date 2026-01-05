import json
import os
from pathlib import Path
from typing import Optional

ROOT_DIR = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT_DIR / "config"
ENV_CONFIG_PATH = CONFIG_DIR / "env.json"
SERVER_CONFIG_PATH = CONFIG_DIR / "server.json"
EVENTS_PROMPT_PATH = CONFIG_DIR / "prompt_events_parse.txt"
HMS_TOKEN_PATH = CONFIG_DIR / "hms_token.txt"
LOG_DIR = ROOT_DIR / "logs"
LOG_PATH = LOG_DIR / "requests.log"


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"配置文件解析失败: {path}") from exc


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError as exc:
        raise RuntimeError(f"提示词文件不存在: {path}") from exc


def get_environment() -> str:
    env_cfg = load_json(ENV_CONFIG_PATH)
    return env_cfg.get("environment", "dev")


def get_dashscope_base_url(env: str) -> str:
    env_cfg = load_json(ENV_CONFIG_PATH)
    base_map = env_cfg.get("dashscope_base_url", {})
    return base_map.get(env, "https://dashscope.aliyuncs.com/api/v1")


def get_dashscope_compatible_base_url(env: str) -> str:
    env_cfg = load_json(ENV_CONFIG_PATH)
    base_map = env_cfg.get("dashscope_compatible_base_url", {})
    return base_map.get(env, "https://dashscope.aliyuncs.com/compatible-mode/v1")


def get_dashscope_api_key(env: str) -> Optional[str]:
    env_cfg = load_json(ENV_CONFIG_PATH)
    key_map = env_cfg.get("dashscope_api_key", {})
    return key_map.get(env) or os.getenv("DASHSCOPE_API_KEY")


def get_firebase_service_account_path(env: str) -> Optional[str]:
    env_cfg = load_json(ENV_CONFIG_PATH)
    path_map = env_cfg.get("firebase_service_account", {})
    return path_map.get(env) or os.getenv("FIREBASE_SERVICE_ACCOUNT")


def get_hms_client_id(env: str) -> Optional[str]:
    env_cfg = load_json(ENV_CONFIG_PATH)
    key_map = env_cfg.get("hms_client_id", {})
    return key_map.get(env) or os.getenv("HMS_CLIENT_ID")


def get_hms_client_secret(env: str) -> Optional[str]:
    env_cfg = load_json(ENV_CONFIG_PATH)
    key_map = env_cfg.get("hms_client_secret", {})
    return key_map.get(env) or os.getenv("HMS_CLIENT_SECRET")


def get_hms_app_id(env: str) -> Optional[str]:
    env_cfg = load_json(ENV_CONFIG_PATH)
    app_map = env_cfg.get("hms_app_id", {})
    return app_map.get(env) or os.getenv("HMS_APP_ID")


def get_server_config(env: str) -> dict:
    server_cfg = load_json(SERVER_CONFIG_PATH)
    cfg = server_cfg.get(env, {})
    return {
        "host": cfg.get("host", "0.0.0.0"),
        "port": int(cfg.get("port", 8000)),
        "reload": bool(cfg.get("reload", env == "dev")),
        "log_level": cfg.get("log_level", "info"),
    }
