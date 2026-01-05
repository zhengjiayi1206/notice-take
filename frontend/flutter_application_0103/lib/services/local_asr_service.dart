import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/asr_config.dart';

class LocalAsrService {
  Future<String> transcribeFile(String path) async {
    final uri = Uri.parse('$localAsrBaseUrl/asr');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('audio', path));

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception('ASR failed: ${response.statusCode} $body');
    }

    return _parseText(body);
  }

  String _parseText(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final text = data['text'] ?? data['result'] ?? data['transcript'];
        if (text is String && text.isNotEmpty) {
          return text;
        }
      }
    } catch (_) {
      // Plain text response.
    }
    return body;
  }
}
