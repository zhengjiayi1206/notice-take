import json
import logging
from pathlib import Path
from typing import Optional


def setup_logger(log_path: Path, name: str = "notice_take") -> logging.Logger:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger(name)
    if logger.handlers:
        return logger
    logger.setLevel(logging.INFO)
    handler = logging.FileHandler(log_path, encoding="utf-8")
    formatter = logging.Formatter(
        fmt="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    return logger


def log_event(
    logger: logging.Logger,
    name: str,
    status: str,
    payload: dict,
    result: Optional[dict],
    error: Optional[str],
) -> None:
    logger.info(
        "%s status=%s payload=%s result=%s error=%s",
        name,
        status,
        json.dumps(payload, ensure_ascii=False),
        json.dumps(result, ensure_ascii=False) if result is not None else "null",
        error,
    )
