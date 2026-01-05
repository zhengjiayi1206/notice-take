import 'package:permission_handler/permission_handler.dart';

class NotificationPermissionService {
  Future<PermissionStatus> ensurePermission() async {
    final status = await Permission.notification.status;
    if (status == PermissionStatus.granted) {
      return status;
    }
    return Permission.notification.request();
  }

  Future<bool> openSettings() {
    return openAppSettings();
  }
}
