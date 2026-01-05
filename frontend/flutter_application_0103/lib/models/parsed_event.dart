class ParsedEvent {
  ParsedEvent({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.isRecurring,
    required this.recurrence,
    required this.summary,
    this.detail,
  });

  final String id;
  final String title;
  final DateTime dateTime;
  final bool isRecurring;
  final RecurrenceRule recurrence;
  final String summary;
  final String? detail;

  String get formattedDateTime =>
      '${dateTime.month}月${dateTime.day}日 ${_two(dateTime.hour)}:${_two(dateTime.minute)}';

  String get formattedTime => '${_two(dateTime.hour)}:${_two(dateTime.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  factory ParsedEvent.fromApi(Map<String, dynamic> data, {DateTime? reference}) {
    final now = reference ?? DateTime.now();
    final rule = data['规则'];
    final ruleMap = rule is Map<String, dynamic> ? rule : const <String, dynamic>{};
    final isRecurring = data['是否循环'] == true;
    final recurrenceRaw = data['循环规律'];
    final recurrence = RecurrenceRule.fromApi(
      isRecurring: isRecurring,
      frequency: recurrenceRaw is String ? recurrenceRaw : null,
      rule: ruleMap,
    );
    final title = _stringOrFallback(ruleMap['事件描述'], data['事件基本描述'], '事项提醒');
    final detail = _stringOrNull(ruleMap['补充说明']);
    final summary = _stringOrFallback(data['事件基本描述'], title, title);
    final recurrenceKey = _normalizeFrequency(recurrenceRaw is String ? recurrenceRaw : null);
    final useWeekday = isRecurring && recurrenceKey == '周';
    final eventTime = _extractDateTime(ruleMap, title, now, useWeekday: useWeekday);
    return ParsedEvent(
      id: 'evt-${DateTime.now().millisecondsSinceEpoch}-${eventTime.hashCode}',
      title: title,
      dateTime: eventTime,
      isRecurring: isRecurring,
      recurrence: recurrence,
      summary: summary,
      detail: detail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'dateTime': dateTime.toIso8601String(),
      'isRecurring': isRecurring,
      'recurrence': recurrence.toJson(),
      'summary': summary,
      'detail': detail,
    };
  }

  factory ParsedEvent.fromJson(Map<String, dynamic> json) {
    final recurrenceRaw = json['recurrence'];
    final recurrence = recurrenceRaw is Map<String, dynamic>
        ? RecurrenceRule.fromJson(recurrenceRaw)
        : RecurrenceRule.none();
    return ParsedEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '事项提醒',
      dateTime: DateTime.tryParse(json['dateTime'] as String? ?? '') ?? DateTime.now(),
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrence: recurrence,
      summary: json['summary'] as String? ?? '',
      detail: json['detail'] as String?,
    );
  }
}

class RecurrenceRule {
  const RecurrenceRule({required this.frequency, this.day, this.month, this.year, this.weekday});

  final String frequency;
  final int? day;
  final int? month;
  final int? year;
  final String? weekday;

  String get label {
    if (frequency == '无') {
      return '不循环';
    }
    if (frequency == '天') {
      return '每天';
    }
    if (frequency == '周' && weekday != null) {
      return '每$weekday';
    }
    if (frequency == '月' && day != null) {
      return '每月$day日';
    }
    if (frequency == '年' && month != null && day != null) {
      return '每年$month月$day日';
    }
    return '循环$frequency';
  }

  factory RecurrenceRule.none() => const RecurrenceRule(frequency: '无');

  factory RecurrenceRule.weekly(String weekday) =>
      RecurrenceRule(frequency: '周', weekday: weekday);

  factory RecurrenceRule.fromApi({
    required bool isRecurring,
    required String? frequency,
    required Map<String, dynamic> rule,
  }) {
    if (!isRecurring) {
      return RecurrenceRule.none();
    }
    final normalized = _normalizeFrequency(frequency);
    if (normalized == '周') {
      final weekday = _stringOrNull(rule['星期几']);
      if (weekday != null && weekday.isNotEmpty) {
        return RecurrenceRule(frequency: normalized, weekday: weekday);
      }
    }
    if (normalized == '月') {
      return RecurrenceRule(
        frequency: normalized,
        day: _parseInt(rule['日']),
      );
    }
    if (normalized == '年') {
      return RecurrenceRule(
        frequency: normalized,
        month: _parseInt(rule['月']),
        day: _parseInt(rule['日']),
      );
    }
    return RecurrenceRule(frequency: normalized);
  }

  Map<String, dynamic> toJson() {
    return {
      'frequency': frequency,
      'day': day,
      'month': month,
      'year': year,
      'weekday': weekday,
    };
  }

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    return RecurrenceRule(
      frequency: json['frequency'] as String? ?? '无',
      day: json['day'] as int?,
      month: json['month'] as int?,
      year: json['year'] as int?,
      weekday: json['weekday'] as String?,
    );
  }
}

String? _stringOrNull(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String _stringOrFallback(Object? primary, Object? fallback, String defaultValue) {
  final primaryText = _stringOrNull(primary);
  if (primaryText != null) {
    return primaryText;
  }
  final fallbackText = _stringOrNull(fallback);
  return fallbackText ?? defaultValue;
}

int? _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    final digits = RegExp(r'\d+').stringMatch(value);
    if (digits != null) {
      return int.tryParse(digits);
    }
  }
  return null;
}

String _normalizeFrequency(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return '无';
  }
  if (raw.contains('天')) {
    return '天';
  }
  if (raw.contains('周') || raw.contains('星期')) {
    return '周';
  }
  if (raw.contains('月')) {
    return '月';
  }
  if (raw.contains('年')) {
    return '年';
  }
  return raw;
}

DateTime _extractDateTime(
  Map<String, dynamic> rule,
  String title,
  DateTime now, {
  bool useWeekday = true,
}) {
  final date = _extractDate(rule, now, title, useWeekday: useWeekday);
  final time = _extractTimeFromRule(rule) ?? _extractTime(title);
  return DateTime(date.year, date.month, date.day, time.item1, time.item2);
}

DateTime _extractDate(
  Map<String, dynamic> rule,
  DateTime now,
  String title, {
  bool useWeekday = true,
}) {
  final yearRaw = _stringOrNull(rule['年']);
  final monthRaw = _stringOrNull(rule['月']);
  final dayRaw = _stringOrNull(rule['日']);
  final weekdayRaw = _stringOrNull(rule['星期几']);
  final hasExplicitDate = yearRaw != null || monthRaw != null || dayRaw != null;

  int year = now.year;
  if (yearRaw != null) {
    if (yearRaw.contains('明年')) {
      year = now.year + 1;
    } else if (yearRaw.contains('今年')) {
      year = now.year;
    } else {
      year = _parseInt(yearRaw) ?? year;
    }
  }

  int month = now.month;
  if (monthRaw != null) {
    if (monthRaw.contains('下月') || monthRaw.contains('下个月')) {
      month = now.month == 12 ? 1 : now.month + 1;
      if (now.month == 12) {
        year += 1;
      }
    } else if (monthRaw.contains('本月') || monthRaw.contains('这个月')) {
      month = now.month;
    } else {
      month = _parseInt(monthRaw) ?? month;
    }
  }

  int day = now.day;
  if (dayRaw != null) {
    if (dayRaw.contains('明天')) {
      final target = now.add(const Duration(days: 1));
      year = target.year;
      month = target.month;
      day = target.day;
    } else if (dayRaw.contains('后天')) {
      final target = now.add(const Duration(days: 2));
      year = target.year;
      month = target.month;
      day = target.day;
    } else if (dayRaw.contains('今天')) {
      day = now.day;
    } else {
      day = _parseInt(dayRaw) ?? day;
    }
  }

  if (useWeekday && weekdayRaw != null && !hasExplicitDate) {
    final weekday = _weekdayToInt(weekdayRaw);
    if (weekday != null) {
      final daysAhead = (weekday - now.weekday + 7) % 7;
      final target = now.add(Duration(days: daysAhead == 0 ? 7 : daysAhead));
      return DateTime(target.year, target.month, target.day);
    }
  }

  final candidate = DateTime(year, month, day);
  if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
    return candidate.add(const Duration(days: 1));
  }
  return candidate;
}

_TimePair _extractTime(String text) {
  final lower = text;
  final match = RegExp(r'(\d{1,2})\s*(?:[:点时])\s*(\d{1,2})?').firstMatch(lower);
  int hour = 9;
  int minute = 0;
  if (match != null) {
    hour = int.tryParse(match.group(1) ?? '') ?? hour;
    if (match.group(2) != null) {
      minute = int.tryParse(match.group(2) ?? '') ?? minute;
    } else if (lower.contains('半')) {
      minute = 30;
    }
  }
  if (lower.contains('下午') || lower.contains('晚上')) {
    if (hour < 12) {
      hour += 12;
    }
  }
  if (lower.contains('中午') && hour < 11) {
    hour += 12;
  }
  return _TimePair(hour.clamp(0, 23).toInt(), minute.clamp(0, 59).toInt());
}

_TimePair? _extractTimeFromRule(Map<String, dynamic> rule) {
  final timeRaw = _stringOrNull(rule['时间']);
  if (timeRaw == null) {
    return null;
  }
  final match = RegExp(r'(\d{1,2})\s*:\s*(\d{1,2})').firstMatch(timeRaw);
  if (match == null) {
    return null;
  }
  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) {
    return null;
  }
  return _TimePair(hour.clamp(0, 23).toInt(), minute.clamp(0, 59).toInt());
}

int? _weekdayToInt(String raw) {
  if (raw.contains('一')) return DateTime.monday;
  if (raw.contains('二')) return DateTime.tuesday;
  if (raw.contains('三')) return DateTime.wednesday;
  if (raw.contains('四')) return DateTime.thursday;
  if (raw.contains('五')) return DateTime.friday;
  if (raw.contains('六')) return DateTime.saturday;
  if (raw.contains('日') || raw.contains('天')) return DateTime.sunday;
  return null;
}

class _TimePair {
  const _TimePair(this.item1, this.item2);

  final int item1;
  final int item2;
}
