# flutter_application_1

A new Flutter project.

## 应用描述
这是一个用于记录事项和提醒的应用。用户可以用白话文录音或打字输入要做的事，系统会把录音转成文字，并通过大模型理解内容，拆解成一个或多个具体事项与时间安排。解析结果会以列表形式展示，用户可逐条查看并删除。到达指定时间时，应用会通过弹窗或打开应用界面提醒用户。同时，页面上方可按日期切换查看未来事件，事件按时间从早到晚排列并用颜色标识是否有安排。

### 录音与文字输入
- 默认通过按键录音输入音频
- 可切换为文字输入，在输入框中打字

### 大模型理解事项
录完音频后立即识别文字，大模型解析为固定格式的事项列表：
```
[{
  是否循环: boolean,
  循环规律: 天/周/月/年,
  事项: {日:, 月:, 年:, 星期几:, 事件描述:, 补充说明:(optional)},
  整体事件描述
}]
```
一段音频可能包含多个事件，所以解析结果是 list。

### 解析后展示
- 解析后的事项在页面中分条展示
- 每条事项右侧有删除按钮，可移除该事项

### 到时间提醒
- 通过弹窗提示用户

### 展示未来事件
- 页面上部显示“日”并可左右切换日期
- 多日视图按列从上到下展示当日事件
- 事件按时间从早到晚排序，并用颜色标识是否有安排

## 配置

- `lib/config/asr_config.dart`：设置后端/ASR 服务地址（`localAsrBaseUrl`，用于 `/asr` 与 `/events/parse`）
- `android/app/agconnect-services.json`：华为推送（HMS）配置文件，需要从 AGC 控制台下载并放置到该路径

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
