import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/parsed_event.dart';
import '../services/event_parse_service.dart';
import '../services/local_asr_service.dart';
import '../services/local_notification_service.dart';
import '../services/notification_permission_service.dart';
import 'event_list_page.dart';
import 'event_page.dart';
import 'shared_widgets.dart';

class NoteHomePage extends StatefulWidget {
  const NoteHomePage({super.key});

  @override
  State<NoteHomePage> createState() => _NoteHomePageState();
}

class _NoteHomePageState extends State<NoteHomePage> {
  final TextEditingController _textController = TextEditingController();
  final List<ParsedEvent> _events = [];
  final LocalAsrService _asrService = LocalAsrService();
  final EventParseService _parseService = EventParseService();
  final NotificationPermissionService _notificationService = NotificationPermissionService();
  final AudioRecorder _recorder = AudioRecorder();
  final ValueNotifier<List<ParsedEvent>> _draftNotifier = ValueNotifier([]);
  final GlobalKey _recordBarKey = GlobalKey();
  static const String _eventsStorageKey = 'stored_events';
  static const String _notificationLogKey = 'notification_logs';
  final Map<String, Timer> _notificationTimers = {};

  bool _textMode = false;
  bool _isRecording = false;
  bool _startInProgress = false;
  bool _pendingStop = false;
  int _pageIndex = 0;
  DateTime _selectedDate = DateTime.now();
  bool _showDraftCard = false;
  bool _showEditCard = false;
  ParsedEvent? _editingEvent;
  double _recordBarHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
    _loadStoredEvents();
  }

  @override
  void dispose() {
    _textController.dispose();
    _draftNotifier.dispose();
    _recorder.dispose();
    for (final timer in _notificationTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  void _toggleInputMode() {
    setState(() {
      _textMode = !_textMode;
    });
  }

  void _updateRecordBarHeight() {
    final context = _recordBarKey.currentContext;
    if (context == null) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final nextHeight = box.size.height;
    if ((nextHeight - _recordBarHeight).abs() > 1) {
      setState(() {
        _recordBarHeight = nextHeight;
      });
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _startInProgress) {
      return;
    }
    _startInProgress = true;
    _pendingStop = false;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _startInProgress = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限才能录音。')),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: path,
      );
    } catch (error) {
      _startInProgress = false;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动录音失败：$error')),
      );
      return;
    }

    setState(() {
      _isRecording = true;
    });
    _startInProgress = false;
    if (_pendingStop) {
      _pendingStop = false;
      await _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (_startInProgress && !_isRecording) {
      _pendingStop = true;
      return;
    }
    if (!_isRecording) {
      return;
    }
    _pendingStop = false;
    final isActuallyRecording = await _recorder.isRecording();
    if (!isActuallyRecording) {
      setState(() {
        _isRecording = false;
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音未开始或已停止，请重试。')),
      );
      return;
    }

    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
    });

    if (path == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音未保存，请重试。')),
      );
      return;
    }

    final file = File(path);
    final fileExists = await file.exists();
    if (!fileExists) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录音文件不存在，请重试。')),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('录音完成'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, _recordBarHeight + 16),
      ),
    );

    try {
      final text = await _asrService.transcribeFile(path);
      await _parseEventsFromText(text);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('调用模型失败：$error')),
      );
    }
  }

  void _parseFromText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入一段描述。')),
      );
      return;
    }
    _textController.clear();
    setState(() {});
    _parseEventsFromText(text);
  }

  void _deleteEvent(ParsedEvent event) {
    setState(() {
      _events.removeWhere((e) => e.id == event.id);
    });
    _notificationTimers.remove(event.id)?.cancel();
    _persistEvents();
  }

  void _shiftDate(int days) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day + days,
      );
    });
  }

  Future<void> _showReminder(ParsedEvent event) async {
    await LocalNotificationService.requestPermissions();
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) {
      return;
    }
    final title = event.title;
    final detail = event.detail ?? '';
    final body = detail.isEmpty ? event.formattedDateTime : '${event.formattedDateTime}\n$detail';
    final id = event.id.hashCode & 0x7fffffff;
    await LocalNotificationService.showNotification(
      id: id,
      title: title,
      body: body,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送系统提醒。')),
    );
  }

  void _editEvent(ParsedEvent event) {
    setState(() {
      _editingEvent = event;
      _showEditCard = true;
      _showDraftCard = false;
    });
  }

  Future<void> _loadStoredEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_eventsStorageKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }
    final items = decoded
        .whereType<Map<String, dynamic>>()
        .map(ParsedEvent.fromJson)
        .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _events
        ..clear()
        ..addAll(items);
    });
  }

  Future<void> _persistEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _events.map((event) => event.toJson()).toList();
    await prefs.setString(_eventsStorageKey, jsonEncode(data));
  }

  Future<void> _scheduleEventReminder(ParsedEvent event) async {
    final next = _nextOccurrence(event);
    if (next == null) {
      _appendNotificationLog('skip ${event.id}: no next occurrence');
      return;
    }
    final delay = next.difference(DateTime.now());
    if (delay <= Duration.zero) {
      _appendNotificationLog('skip ${event.id}: time already passed (${next.toIso8601String()})');
      return;
    }
    final title = event.title;
    final detail = event.detail ?? '';
    final timeLabel = _formatDateTime(next);
    final body = detail.isEmpty ? timeLabel : '$timeLabel\n$detail';
    final id = event.id.hashCode & 0x7fffffff;
    await LocalNotificationService.scheduleReminder(
      id: id,
      title: title,
      body: body,
      scheduledAt: next,
    );
    _appendNotificationLog(
      'scheduled ${event.id} at ${next.toIso8601String()} (in ${delay.inSeconds}s)',
    );
    _notificationTimers.remove(event.id)?.cancel();
    if (delay <= const Duration(hours: 24)) {
      _notificationTimers[event.id] = Timer(delay, () {
        _appendNotificationLog('due ${event.id} at ${DateTime.now().toIso8601String()}');
        LocalNotificationService.showNotification(
          id: id,
          title: title,
          body: body,
        );
      });
    }
  }

  Future<void> _appendNotificationLog(String message) async {
    debugPrint(message);
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_notificationLogKey) ?? <String>[];
    final stamped = '[${DateTime.now().toIso8601String()}] $message';
    final updated = [...existing, stamped];
    if (updated.length > 50) {
      updated.removeRange(0, updated.length - 50);
    }
    await prefs.setStringList(_notificationLogKey, updated);
  }

  Future<void> _requestNotificationPermission({bool fromUserAction = false}) async {
    final status = await _notificationService.ensurePermission();
    if (!mounted) {
      return;
    }
    if (status == PermissionStatus.granted) {
      if (fromUserAction) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知权限已开启。')),
        );
      }
      return;
    }
    if (fromUserAction) {
      final opened = await _notificationService.openSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开系统设置，请手动开启通知权限。')),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('需要通知权限才能提醒，请在系统设置中开启。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pages = [
      EventListPage(
        events: _events,
        onDelete: _deleteEvent,
        onReminder: _showReminder,
        onEdit: _editEvent,
      ),
      EventPage(
        events: _events,
        selectedDate: _selectedDate,
        onReminder: _showReminder,
        onPrevDate: () => _shiftDate(-1),
        onNextDate: () => _shiftDate(1),
      ),
    ];
    final bottomSpacer =
        (_textMode ? 180.0 : 96.0) + MediaQuery.of(context).padding.bottom;
    final showOverlay = _showDraftCard || (_showEditCard && _editingEvent != null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRecordBarHeight());
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(
            child: FuturisticBackground(animate: true),
          ),
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _PageSwitcher(
                    currentIndex: _pageIndex,
                    onChanged: (value) => setState(() => _pageIndex = value),
                    onNotificationPressed: () =>
                        _requestNotificationPermission(fromUserAction: true),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: pages[_pageIndex]),
                  SizedBox(height: bottomSpacer),
                ],
              ),
            ),
          ),
          if (showOverlay)
            Positioned.fill(
              child: ModalBarrier(
                color: Colors.black.withOpacity(0.55),
                dismissible: false,
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SizedBox(
                key: _recordBarKey,
                child: _RecordBar(
                  isRecording: _isRecording,
                  isTextMode: _textMode,
                  textController: _textController,
                  onStartRecording: _startRecording,
                  onStopRecording: _stopRecording,
                  onParseText: _parseFromText,
                  onToggleInputMode: _toggleInputMode,
                ),
              ),
            ),
          ),
          if (showOverlay)
            Positioned.fill(
              child: Stack(
                children: [
                  if (_showDraftCard)
                    _CenteredOverlay(
                      bottomPadding: _recordBarHeight + bottomInset,
                      child: _DraftCard(
                        draftListenable: _draftNotifier,
                        onClose: () => setState(() => _showDraftCard = false),
                        onConfirm: (updated) {
                          if (updated.isEmpty) {
                            return;
                          }
                          setState(() {
                            _events.insertAll(0, updated);
                            _showDraftCard = false;
                          });
                          for (final event in updated) {
                            _scheduleEventReminder(event);
                          }
                          _persistEvents();
                        },
                      ),
                    ),
                  if (_showEditCard && _editingEvent != null)
                    _CenteredOverlay(
                      bottomPadding: _recordBarHeight + bottomInset,
                      child: _EditCard(
                        event: _editingEvent!,
                        onClose: () => setState(() => _showEditCard = false),
                        onSave: (updated) {
                          setState(() {
                            final index = _events.indexWhere((item) => item.id == updated.id);
                            if (index != -1) {
                              _events[index] = updated;
                            }
                            _showEditCard = false;
                          });
                          _scheduleEventReminder(updated);
                          _persistEvents();
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Future<void> _parseEventsFromText(String text) async {
    try {
      final parsedEvents = await _parseService.parseText(text);
      if (!mounted) {
        return;
      }
      if (parsedEvents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有解析出事项，请换种说法再试。')),
        );
        return;
      }
      await _openOrUpdateDraftSheet(parsedEvents);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('事项解析失败：$error')),
      );
    }
  }

  Future<void> _openOrUpdateDraftSheet(List<ParsedEvent> parsedEvents) async {
    _draftNotifier.value = parsedEvents;
    setState(() {
      _showDraftCard = true;
      _showEditCard = false;
      _editingEvent = null;
    });
  }
}

class _DraftCard extends StatefulWidget {
  const _DraftCard({
    required this.draftListenable,
    required this.onConfirm,
    required this.onClose,
  });

  final ValueListenable<List<ParsedEvent>> draftListenable;
  final ValueChanged<List<ParsedEvent>> onConfirm;
  final VoidCallback onClose;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  List<ParsedEvent> _events = [];
  List<TextEditingController> _titleControllers = [];
  List<TextEditingController> _detailControllers = [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.draftListenable.value);
    widget.draftListenable.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    widget.draftListenable.removeListener(_onDraftChanged);
    for (final controller in _titleControllers) {
      controller.dispose();
    }
    for (final controller in _detailControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onDraftChanged() {
    _syncControllers(widget.draftListenable.value);
  }

  void _syncControllers(List<ParsedEvent> events) {
    final oldTitle = _titleControllers;
    final oldDetail = _detailControllers;
    final newTitle = <TextEditingController>[];
    final newDetail = <TextEditingController>[];
    for (final event in events) {
      newTitle.add(TextEditingController(text: event.title));
      newDetail.add(TextEditingController(text: event.detail ?? ''));
    }
    setState(() {
      _events = events;
      _titleControllers = newTitle;
      _detailControllers = newDetail;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in oldTitle) {
        controller.dispose();
      }
      for (final controller in oldDetail) {
        controller.dispose();
      }
    });
  }

  Future<void> _editSchedule(int index) async {
    final event = _events[index];
    final result = await _openScheduleEditor(context, event);
    if (result == null) {
      return;
    }
    setState(() {
      _events[index] = ParsedEvent(
        id: event.id,
        title: event.title,
        dateTime: result.dateTime,
        isRecurring: result.isRecurring,
        recurrence: result.recurrence,
        summary: event.summary,
        detail: event.detail,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    '确认事项',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final event = _events[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5F1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '事项 ${index + 1}',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _titleControllers[index],
                        decoration: const InputDecoration(
                          labelText: '事项内容',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _detailControllers[index],
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '补充说明（可选）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          GestureDetector(
                            onTap: () => _editSchedule(index),
                            child: InfoPill(
                              icon: Icons.schedule,
                              label: event.formattedDateTime,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _editSchedule(index),
                            child: InfoPill(
                              icon: Icons.event_repeat,
                              label: event.isRecurring ? event.recurrence.label : '一次性',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final updated = <ParsedEvent>[];
                    for (var i = 0; i < _events.length; i++) {
                      final base = _events[i];
                      final title = _titleControllers[i].text.trim();
                      final detail = _detailControllers[i].text.trim();
                      updated.add(
                        ParsedEvent(
                          id: base.id,
                          title: title.isEmpty ? base.title : title,
                          dateTime: base.dateTime,
                          isRecurring: base.isRecurring,
                          recurrence: base.recurrence,
                          summary: title.isEmpty ? base.summary : title,
                          detail: detail.isEmpty ? null : detail,
                        ),
                      );
                    }
                    widget.onConfirm(updated);
                  },
                  child: const Text('加入事项'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditCard extends StatefulWidget {
  const _EditCard({
    required this.event,
    required this.onSave,
    required this.onClose,
  });

  final ParsedEvent event;
  final ValueChanged<ParsedEvent> onSave;
  final VoidCallback onClose;

  @override
  State<_EditCard> createState() => _EditCardState();
}

class _EditCardState extends State<_EditCard> {
  late final TextEditingController _titleController;
  late final TextEditingController _detailController;
  late DateTime _dateTime;
  late bool _isRecurring;
  late RecurrenceRule _recurrence;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.title);
    _detailController = TextEditingController(text: widget.event.detail ?? '');
    _dateTime = widget.event.dateTime;
    _isRecurring = widget.event.isRecurring;
    _recurrence = widget.event.recurrence;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    '编辑事项',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: '事项内容',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _detailController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '补充说明（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: _editSchedule,
                        child: InfoPill(
                          icon: Icons.schedule,
                          label: _formatDateTime(_dateTime),
                        ),
                      ),
                      GestureDetector(
                        onTap: _editSchedule,
                        child: InfoPill(
                          icon: Icons.event_repeat,
                          label: _isRecurring ? _recurrence.label : '一次性',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final title = _titleController.text.trim();
                    final detail = _detailController.text.trim();
                    widget.onSave(
                      ParsedEvent(
                        id: widget.event.id,
                        title: title.isEmpty ? widget.event.title : title,
                        dateTime: _dateTime,
                        isRecurring: _isRecurring,
                        recurrence: _recurrence,
                        summary: title.isEmpty ? widget.event.summary : title,
                        detail: detail.isEmpty ? null : detail,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editSchedule() async {
    final result = await _openScheduleEditor(
      context,
      ParsedEvent(
        id: widget.event.id,
        title: widget.event.title,
        dateTime: _dateTime,
        isRecurring: _isRecurring,
        recurrence: _recurrence,
        summary: widget.event.summary,
        detail: widget.event.detail,
      ),
    );
    if (result == null) {
      return;
    }
    setState(() {
      _dateTime = result.dateTime;
      _isRecurring = result.isRecurring;
      _recurrence = result.recurrence;
    });
  }
}

class _ScheduleResult {
  const _ScheduleResult({
    required this.dateTime,
    required this.isRecurring,
    required this.recurrence,
  });

  final DateTime dateTime;
  final bool isRecurring;
  final RecurrenceRule recurrence;
}

Future<_ScheduleResult?> _openScheduleEditor(BuildContext context, ParsedEvent event) {
  final now = DateTime.now();
  final minDate = DateTime(now.year - 1, now.month, now.day);
  final maxDate = DateTime(now.year + 5, 12, 31);
  DateTime tempDateTime = event.dateTime;
  String selectedKey = _recurrenceKeyFromEvent(event);
  bool isRecurring = selectedKey != 'none';
  RecurrenceRule recurrence = _recurrenceFromKey(selectedKey, tempDateTime);

  return showModalBottomSheet<_ScheduleResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickDate() async {
            final date = await showDatePicker(
              context: context,
              initialDate: tempDateTime,
              firstDate: minDate,
              lastDate: maxDate,
            );
            if (date == null) {
              return;
            }
            setState(() {
              tempDateTime = DateTime(
                date.year,
                date.month,
                date.day,
                tempDateTime.hour,
                tempDateTime.minute,
              );
              recurrence = _recurrenceFromKey(selectedKey, tempDateTime);
              isRecurring = selectedKey != 'none';
            });
          }

          Future<void> pickTime() async {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: tempDateTime.hour, minute: tempDateTime.minute),
            );
            if (time == null) {
              return;
            }
            setState(() {
              tempDateTime = DateTime(
                tempDateTime.year,
                tempDateTime.month,
                tempDateTime.day,
                time.hour,
                time.minute,
              );
            });
          }

          void selectRecurrence(String key) {
            setState(() {
              selectedKey = key;
              recurrence = _recurrenceFromKey(selectedKey, tempDateTime);
              isRecurring = selectedKey != 'none';
            });
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          '修改时间与循环',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('日期'),
                  subtitle: Text(_formatDate(tempDateTime)),
                  trailing: TextButton(
                    onPressed: pickDate,
                    child: const Text('选择'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: const Text('时间'),
                  subtitle: Text(_formatTime(tempDateTime)),
                  trailing: TextButton(
                    onPressed: pickTime,
                    child: const Text('选择'),
                  ),
                ),
                const Divider(height: 20),
                Text(
                  '循环规则',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                RadioListTile<String>(
                  value: 'none',
                  groupValue: selectedKey,
                  onChanged: (value) => selectRecurrence(value ?? 'none'),
                  title: const Text('一次性'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  value: 'daily',
                  groupValue: selectedKey,
                  onChanged: (value) => selectRecurrence(value ?? 'daily'),
                  title: const Text('每天'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  value: 'weekly',
                  groupValue: selectedKey,
                  onChanged: (value) => selectRecurrence(value ?? 'weekly'),
                  title: Text('每${_weekdayLabel(tempDateTime)}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  value: 'monthly',
                  groupValue: selectedKey,
                  onChanged: (value) => selectRecurrence(value ?? 'monthly'),
                  title: Text('每月${tempDateTime.day}日'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  value: 'yearly',
                  groupValue: selectedKey,
                  onChanged: (value) => selectRecurrence(value ?? 'yearly'),
                  title: Text('每年${tempDateTime.month}月${tempDateTime.day}日'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            _ScheduleResult(
                              dateTime: tempDateTime,
                              isRecurring: isRecurring,
                              recurrence: recurrence,
                            ),
                          );
                        },
                        child: const Text('确定'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _recurrenceKeyFromEvent(ParsedEvent event) {
  if (!event.isRecurring) {
    return 'none';
  }
  switch (event.recurrence.frequency) {
    case '天':
      return 'daily';
    case '周':
      return 'weekly';
    case '月':
      return 'monthly';
    case '年':
      return 'yearly';
    default:
      return 'daily';
  }
}

DateTime? _nextOccurrence(ParsedEvent event) {
  final now = DateTime.now();
  final base = event.dateTime;
  if (!event.isRecurring || event.recurrence.frequency == '无') {
    return base.isAfter(now) ? base : null;
  }
  final frequency = event.recurrence.frequency;
  if (frequency == '天') {
    return _nextDaily(base, now);
  }
  if (frequency == '周') {
    return _nextWeekly(base, now);
  }
  if (frequency == '月') {
    return _nextMonthly(base, now);
  }
  if (frequency == '年') {
    return _nextYearly(base, now);
  }
  return base.isAfter(now) ? base : null;
}

DateTime _nextDaily(DateTime base, DateTime now) {
  if (!base.isBefore(now)) {
    return base;
  }
  final days = now.difference(base).inDays;
  var next = base.add(Duration(days: days));
  if (next.isBefore(now)) {
    next = next.add(const Duration(days: 1));
  }
  return next;
}

DateTime _nextWeekly(DateTime base, DateTime now) {
  if (!base.isBefore(now)) {
    return base;
  }
  final days = now.difference(base).inDays;
  final weeks = (days / 7).floor();
  var next = base.add(Duration(days: weeks * 7));
  if (next.isBefore(now)) {
    next = next.add(const Duration(days: 7));
  }
  return next;
}

DateTime _nextMonthly(DateTime base, DateTime now) {
  if (!base.isBefore(now)) {
    return base;
  }
  var year = base.year;
  var month = base.month;
  while (DateTime(year, month, 1).isBefore(DateTime(now.year, now.month, 1)) ||
      (year == now.year && month == now.month && _monthInstance(base, year, month).isBefore(now))) {
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  var candidate = _monthInstance(base, year, month);
  if (candidate.isBefore(now)) {
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
    candidate = _monthInstance(base, year, month);
  }
  return candidate;
}

DateTime _nextYearly(DateTime base, DateTime now) {
  if (!base.isBefore(now)) {
    return base;
  }
  var year = now.year;
  var candidate = _yearInstance(base, year);
  if (candidate.isBefore(now)) {
    candidate = _yearInstance(base, year + 1);
  }
  return candidate;
}

DateTime _monthInstance(DateTime base, int year, int month) {
  final day = base.day;
  final lastDay = DateTime(year, month + 1, 0).day;
  final safeDay = day > lastDay ? lastDay : day;
  return DateTime(year, month, safeDay, base.hour, base.minute);
}

DateTime _yearInstance(DateTime base, int year) {
  final month = base.month;
  final day = base.day;
  final lastDay = DateTime(year, month + 1, 0).day;
  final safeDay = day > lastDay ? lastDay : day;
  return DateTime(year, month, safeDay, base.hour, base.minute);
}

RecurrenceRule _recurrenceFromKey(String key, DateTime date) {
  switch (key) {
    case 'daily':
      return const RecurrenceRule(frequency: '天');
    case 'weekly':
      return RecurrenceRule.weekly(_weekdayLabel(date));
    case 'monthly':
      return RecurrenceRule(frequency: '月', day: date.day);
    case 'yearly':
      return RecurrenceRule(frequency: '年', month: date.month, day: date.day);
    case 'none':
    default:
      return RecurrenceRule.none();
  }
}

String _formatDate(DateTime dateTime) {
  return '${dateTime.month}月${dateTime.day}日 ${_weekdayLabel(dateTime)}';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _weekdayLabel(DateTime date) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return labels[date.weekday - 1];
}

class _CenteredOverlay extends StatelessWidget {
  const _CenteredOverlay({
    required this.child,
    this.bottomPadding = 0,
  });

  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomPadding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: Material(
                color: Colors.white,
                elevation: 16,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordBar extends StatelessWidget {
  const _RecordBar({
    required this.isRecording,
    required this.isTextMode,
    required this.textController,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onParseText,
    required this.onToggleInputMode,
  });

  final bool isRecording;
  final bool isTextMode;
  final TextEditingController textController;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onParseText;
  final VoidCallback onToggleInputMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const buttonHeight = 48.0;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          child: isTextMode
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: textController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '输入事项描述，例如：明早 9 点开会',
                        filled: true,
                        fillColor: const Color(0xFFF8F5F1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onParseText,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('生成事项'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, buttonHeight),
                              padding: buttonPadding,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: onToggleInputMode,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.primary,
                            side: BorderSide(color: theme.colorScheme.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: buttonPadding,
                            minimumSize: const Size(0, buttonHeight),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic, size: 18),
                              SizedBox(width: 6),
                              Text('语音'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => onStartRecording(),
                        onPointerUp: (_) => onStopRecording(),
                        onPointerCancel: (_) => onStopRecording(),
                        child: Container(
                          height: buttonHeight,
                          padding: buttonPadding,
                          decoration: BoxDecoration(
                            color:
                                isRecording ? const Color(0xFFFF6B6B) : theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isRecording ? Icons.stop_circle : Icons.mic,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isRecording ? '松手结束' : '按住说话',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: onToggleInputMode,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(color: theme.colorScheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: buttonPadding,
                        minimumSize: const Size(0, buttonHeight),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard, size: 18),
                          SizedBox(width: 6),
                          Text('文字'),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PageSwitcher extends StatelessWidget {
  const _PageSwitcher({
    required this.currentIndex,
    required this.onChanged,
    required this.onNotificationPressed,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onNotificationPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _SwitchButton(
                  label: '事项清单',
                  isActive: currentIndex == 0,
                  onTap: () => onChanged(0),
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _SwitchButton(
                  label: '时间轴',
                  isActive: currentIndex == 1,
                  onTap: () => onChanged(1),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: onNotificationPressed,
            icon: const Icon(Icons.notifications_active),
            tooltip: '通知设置',
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.color,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isActive ? Colors.white : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
