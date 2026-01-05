from pathlib import Path
from typing import Optional

import firebase_admin
from firebase_admin import credentials

firebase_app = None


def get_firebase_app(service_account_path: Optional[str]):
    global firebase_app
    if firebase_app:
        return firebase_app
    if not service_account_path:
        raise RuntimeError("未配置 Firebase Service Account 路径")
    path = Path(service_account_path)
    if not path.exists():
        raise RuntimeError(f"Firebase Service Account 文件不存在: {service_account_path}")
    cred = credentials.Certificate(str(path))
    firebase_app = firebase_admin.initialize_app(cred)
    return firebase_app
