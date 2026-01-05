import 'package:flutter/material.dart';

import '../models/parsed_event.dart';
import 'shared_widgets.dart';

class EventPage extends StatelessWidget {
  const EventPage({
    super.key,
    required this.events,
    required this.selectedDate,
    required this.onReminder,
    required this.onPrevDate,
    required this.onNextDate,
  });

  final List<ParsedEvent> events;
  final DateTime selectedDate;
  final ValueChanged<ParsedEvent> onReminder;
  final VoidCallback onPrevDate;
  final VoidCallback onNextDate;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateSelector(
            date: selectedDate,
            onPrev: onPrevDate,
            onNext: onNextDate,
          ),
          const SizedBox(height: 12),
          _Timeline(
            date: selectedDate,
            events: events
                .where(
                  (event) =>
                      event.dateTime.year == selectedDate.year &&
                      event.dateTime.month == selectedDate.month &&
                      event.dateTime.day == selectedDate.day,
                )
                .toList()
              ..sort((a, b) => a.dateTime.compareTo(b.dateTime)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({required this.date, required this.onPrev, required this.onNext});

  final DateTime date;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = '${date.year}年${date.month}月${date.day}日';
    final relative = _relativeLabel(date);
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                formatted,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '${relative}${_weekdayLabel(date)}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.date, required this.events});

  final DateTime date;
  final List<ParsedEvent> events;

  @override
  Widget build(BuildContext context) {
    final slots = List.generate(
      15,
      (index) => TimeOfDay(hour: 8 + index, minute: 0),
    );

    if (events.isEmpty) {
      return const EmptyState(
        title: '今天还没有安排',
        description: '继续录音或输入生成提醒。',
      );
    }

    return Column(
      children: slots.map((slot) {
        final event = events.where((item) => item.dateTime.hour == slot.hour).toList();
        return _TimelineRow(slot: slot, events: event);
      }).toList(),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.slot, required this.events});

  final TimeOfDay slot;
  final List<ParsedEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEvent = events.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasEvent ? const Color(0xFF146C94) : const Color(0xFFB7C4D6),
                ),
              ),
              Container(
                width: 2,
                height: 60,
                color: const Color(0xFFE2E8F0),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasEvent ? const Color(0xFFFFF4E6) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.format(context),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (hasEvent)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: events
                          .map(
                            (event) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• ${event.title}'),
                            ),
                          )
                          .toList(),
                    )
                  else
                    Text(
                      '暂无事项',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _weekdayLabel(DateTime date) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return labels[date.weekday - 1];
}

String _relativeLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final delta = target.difference(today).inDays;
  if (delta == 0) {
    return '今天 ';
  }
  if (delta == 1) {
    return '明天 ';
  }
  if (delta == 2) {
    return '后天 ';
  }
  if (delta == -1) {
    return '昨天 ';
  }
  if (delta == -2) {
    return '前天 ';
  }
  return '';
}
