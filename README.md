# notice-take monorepo

后端 FastAPI 与前端 Flutter 的统一仓库结构。

```
notice-take/
├── backend/NOTICE_TAKE
└── frontend/flutter_application_0103
```

## 配置索引

后端（FastAPI）：
- 配置文件：`backend/NOTICE_TAKE/config/env.json`（从 `env.example.json` 复制）
- 必填项：`dashscope_api_key`（文本解析接口使用）
- 可选项：`hms_client_id`/`hms_client_secret`/`hms_app_id`（HMS 推送）
- 可选项：`firebase_service_account`（FCM 推送）
- 其他：`backend/NOTICE_TAKE/config/hms_token.txt`（默认 HMS token）

前端（Flutter）：
- API 地址：`frontend/flutter_application_0103/lib/config/asr_config.dart`（`localAsrBaseUrl`）
- HMS 配置：`frontend/flutter_application_0103/android/app/agconnect-services.json`（从 AGC 控制台下载）

## 后端运行

```bash
cd backend/NOTICE_TAKE
cp config/env.example.json config/env.json
uv sync
uv run python app.py
```

## 前端运行

```bash
cd frontend/flutter_application_0103
flutter pub get
flutter run
```
