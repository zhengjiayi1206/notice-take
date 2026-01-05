import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/asr_config.dart';
import '../models/parsed_event.dart';

class EventParseService {
  Future<List<ParsedEvent>> parseText(String content) async {
    final now = DateTime.now();
    final uri = Uri.parse('$localAsrBaseUrl/events/parse');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'content': content,
        'current_date': _formatDate(now),
        'current_weekday': _weekdayLabel(now),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Parse failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      throw Exception('Parse failed: unexpected response ${response.body}');
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map((item) => ParsedEvent.fromApi(item))
        .toList();
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _weekdayLabel(DateTime date) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return labels[date.weekday - 1];
}
