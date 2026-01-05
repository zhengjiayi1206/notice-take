import 'package:flutter/material.dart';
import 'package:huawei_push/huawei_push.dart';

import 'services/local_notification_service.dart';
import 'ui/note_home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotificationService.initialize();
  await initHmsPush();
  runApp(const NoteScheduleApp());
}

Future<void> initHmsPush() async {
  try {
    Push.getToken('');
    Push.getTokenStream.listen((token) {
      debugPrint('HMS token = $token');
    }, onError: (error) {
      debugPrint('HMS token error: $error');
    });
    Push.onMessageReceivedStream.listen((remoteMessage) {
      final title = remoteMessage.notification?.title ?? '新消息';
      final body = remoteMessage.notification?.body ?? '';
      debugPrint(
        'HMS received title="$title" body="$body" data=${remoteMessage.data}',
      );
      LocalNotificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        body: body,
      );
    }, onError: (error) {
      debugPrint('HMS message error: $error');
    });
  } catch (e) {
    debugPrint('HMS token error: $e');
  }
}

class NoteScheduleApp extends StatelessWidget {
  const NoteScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.light(useMaterial3: true);
    return MaterialApp(
      title: '语音记事提醒',
      theme: baseTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF146C94),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F3EF),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const NoteHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
