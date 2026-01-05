import 'package:flutter/material.dart';

import '../models/parsed_event.dart';
import 'shared_widgets.dart';

class EventListPage extends StatelessWidget {
  const EventListPage({
    super.key,
    required this.events,
    required this.onDelete,
    required this.onReminder,
    required this.onEdit,
  });

  final List<ParsedEvent> events;
  final ValueChanged<ParsedEvent> onDelete;
  final ValueChanged<ParsedEvent> onReminder;
  final ValueChanged<ParsedEvent> onEdit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpcomingList(
            events: events,
            onReminder: onReminder,
          ),
          const SizedBox(height: 16),
          const SectionTitle(
            title: '总清单',
          ),
          const SizedBox(height: 12),
          _ParsedEventList(
            events: events,
            onDelete: onDelete,
            onReminder: onReminder,
            onEdit: onEdit,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ParsedEventList extends StatelessWidget {
  const _ParsedEventList({
    required this.events,
    required this.onDelete,
    required this.onReminder,
    required this.onEdit,
  });

  final List<ParsedEvent> events;
  final ValueChanged<ParsedEvent> onDelete;
  final ValueChanged<ParsedEvent> onReminder;
  final ValueChanged<ParsedEvent> onEdit;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyState(
        title: '还没有事项',
        description: '完成一次录音或文字输入后，会自动生成事项。',
      );
    }

    return Column(
      children: events.map((event) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onEdit(event),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(event.summary),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                InfoPill(
                                  icon: Icons.schedule,
                                  label: event.formattedTime,
                                ),
                                InfoPill(
                                  icon: Icons.event_repeat,
                                  label: event.isRecurring ? event.recurrence.label : '一次性',
                                ),
                                if (event.detail != null)
                                  InfoPill(
                                    icon: Icons.notes,
                                    label: event.detail!,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => onReminder(event),
                        icon: const Icon(Icons.notifications_active),
                        tooltip: '预览提醒',
                      ),
                      IconButton(
                        onPressed: () => onDelete(event),
                        icon: const Icon(Icons.close),
                        tooltip: '删除事项',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.events, required this.onReminder});

  final List<ParsedEvent> events;
  final ValueChanged<ParsedEvent> onReminder;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = events
        .where((event) => event.dateTime.isAfter(now))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (upcoming.isEmpty) {
      return const EmptyState(
        title: '暂无即将到来的事项',
        description: '新的事项会自动出现在这里。',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: '近期提醒',
        ),
        const SizedBox(height: 12),
        ...upcoming.take(5).map((event) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF146C94),
                  foregroundColor: Colors.white,
                  child: Icon(Icons.event_available),
                ),
                title: Text(event.title),
                subtitle: Text(event.formattedDateTime),
                trailing: IconButton(
                  onPressed: () => onReminder(event),
                  icon: const Icon(Icons.notifications),
                  tooltip: '预览提醒',
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
