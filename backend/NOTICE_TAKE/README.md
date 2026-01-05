## 项目结构

- `app.py`: 本地启动入口。
- `notice_take/`: FastAPI 业务代码与服务封装。
- `config/`: 环境配置与提示词。
- `logs/`: 请求日志输出目录。

## 配置

在 `config/` 目录下准备本地配置文件：

```bash
cp config/env.example.json config/env.json
```

然后在 `config/env.json` 中填写以下配置（敏感信息不要提交到仓库）：

- `dashscope_api_key`: DashScope API Key（必填）
- `hms_client_id`/`hms_client_secret`/`hms_app_id`: HMS 推送配置（使用 `/hms/send` 时必填）
- `firebase_service_account`: Firebase Service Account JSON 路径（使用 `/push/send` 时必填）

可选配置文件：

- `config/hms_token.txt`: 默认 HMS token（未在接口请求体中传入 token 时使用）
- `config/server.json`: 服务器监听配置（默认使用 `dev`）

## 依赖安装（uv）

```bash
uv sync
```

## 启动

```bash
uv run python app.py
# 或
uvicorn notice_take.app:app --host 0.0.0.0 --port 8000
```

## /events/parse 接口说明

用于将自然语言事项描述解析为固定 JSON 结构的事项列表。

### 请求

- 方法：`POST`
- 路径：`/events/parse`
- Content-Type：`application/json`

#### 请求体参数

```json
{
  "content": "string，必填，用户输入的事项文本",
  "model": "string，可选，默认 qwen-flash",
  "enable_thinking": "boolean，可选，默认 false",
  "current_date": "string，必填，请求时的当前日期，格式 YYYY-MM-DD",
  "current_weekday": "string，必填，请求时的当前星期，如 周一/周二"
}
```

说明：
- `content` 不能为空。
- `model` 为 DashScope OpenAI 兼容接口支持的模型名。
- `enable_thinking` 仅影响模型输出的思考内容，本接口不会返回思考内容。
- `current_date/current_weekday` 由前端传入，用于将相对日期换算为具体日期。

#### 请求示例

```bash
curl -X POST http://localhost:8000/events/parse \
  -H "Content-Type: application/json" \
  -d '{"content":"明天上午9点开周会，每周一重复，提醒准备周报","current_date":"2025-03-11","current_weekday":"周二"}'
```

### 响应

成功时返回 `list`，每个元素为一个事项对象。

#### 事项对象结构

```json
{
  "是否循环": true,
  "循环规律": "天/周/月/年 或 null",
  "规则": {
    "日": "string 或 null",
    "月": "string 或 null",
    "年": "string 或 null",
    "星期几": "string 或 null",
    "事件描述": "string",
    "补充说明": "string 或 null"
  },
  "事件基本描述": "string"
}
```

字段说明：
- `是否循环`: 是否为循环事项。
- `循环规律`: 循环单位，仅在 `是否循环` 为 `true` 时有意义，值为 `天/周/月/年` 或 `null`。只有文本中明确出现“每天/每周/每月/每年/每周一/每周二”等循环表达时才判定为循环，否则一律不循环。
- `规则`: 事件的时间/描述细节，无法解析时可为 `null`。
  - `日/月/年/星期几`: 字符串形式的时间表达。`日` 仅为数字日期（1-31），`月` 仅为数字月份（1-12）；相对日期（今天/明天/后天/本月/下月等）会基于请求时的当前日期换算后输出数字。
  - `星期几` 仅在 `是否循环=true` 且 `循环规律=周` 时有值，否则为 `null`。
  - `时间`: 24 小时制 `HH:00`，如 `09:00`、`14:00`、`19:00`，没有明确时间点则为 `null`。
  - `事件描述`: 事项动作/主体描述。
  - `补充说明`: 可选补充信息。
- `事件基本描述`: 简短的整体描述。

#### 响应示例（单事件）

```json
[
  {
    "是否循环": false,
    "循环规律": null,
    "规则": {
      "日": "12",
      "月": "3",
      "年": "2025",
      "星期几": null,
      "时间": "09:00",
      "事件描述": "开周会",
      "补充说明": "提醒准备周报"
    },
    "事件基本描述": "明天上午9点开周会"
  }
]
```

#### 响应示例（多事件）

```json
[
  {
    "是否循环": false,
    "循环规律": null,
    "规则": {
      "日": "13",
      "月": "3",
      "年": "2025",
      "星期几": null,
      "时间": "11:00",
      "事件描述": "体检",
      "补充说明": null
    },
    "事件基本描述": "后天上午11点体检"
  },
  {
    "是否循环": false,
    "循环规律": null,
    "规则": {
      "日": "1",
      "月": "4",
      "年": "2025",
      "星期几": null,
      "时间": null,
      "事件描述": "交物业费",
      "补充说明": null
    },
    "事件基本描述": "下个月1号交物业费"
  }
]
```

### 错误响应

```json
{
  "detail": "模型调用失败: <错误信息>"
}
```

### 注意事项

- 若无法解析，返回空数组 `[]`。
- 输出为模型生成的结构化结果，建议前端做字段容错处理。
- 相对日期换算基于请求体中的 `current_date/current_weekday`。

## /push/send 接口说明

用于向单个设备 token 发送系统通知（App 被杀也能弹）。

### 依赖与配置

- 安装依赖：`pip install firebase-admin`
- 在 `config/env.json` 配置 `firebase_service_account` 路径，或设置环境变量 `FIREBASE_SERVICE_ACCOUNT`
- Service Account JSON 只放服务器端

### 请求

- 方法：`POST`
- 路径：`/push/send`
- Content-Type：`application/json`

#### 请求体参数

```json
{
  "token": "string，必填，FCM token",
  "title": "string，必填，通知标题",
  "body": "string，必填，通知内容",
  "data": "object，可选，附加数据（值会转换为字符串）"
}
```

#### 请求示例

```bash
curl -X POST http://localhost:8000/push/send \
  -H "Content-Type: application/json" \
  -d '{"token":"YOUR_FCM_TOKEN","title":"新消息","body":"你有一条新消息","data":{"chatId":"123"}}'
```

### 响应

```json
{
  "message_id": "string，Firebase message_id"
}
```

## /hms/send 接口说明

用于通过 HMS（Huawei Push）向单个设备 token 发送系统通知。

### 依赖与配置

- 在 `config/env.json` 配置 `hms_app_id`、`hms_client_id`、`hms_client_secret`，或设置环境变量 `HMS_APP_ID`、`HMS_CLIENT_ID`、`HMS_CLIENT_SECRET`
- 可选：把默认 token 写到 `config/hms_token.txt`

### 请求

- 方法：`POST`
- 路径：`/hms/send`
- Content-Type：`application/json`

#### 请求体参数

```json
{
  "token": "string，可选，HMS token（为空时读取 config/hms_token.txt）",
  "title": "string，必填，通知标题",
  "body": "string，必填，通知内容",
  "data": "object，可选，附加数据",
  "channel_id": "string，可选，通知渠道 id（如 default）"
}
```

#### 请求示例

```bash
curl -X POST http://localhost:8000/hms/send \
  -H "Content-Type: application/json" \
  -d '{"title":"新消息","body":"你有一条新消息","data":{"chatId":"123"}}'
```
