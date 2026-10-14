import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local-only notifications (no push service, no network).
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _backupId = 1001;

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  static Future<bool> requestPermission() async {
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (await a?.requestNotificationsPermission()) ?? false;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'backup_reminder',
      'Backup reminders',
      channelDescription: 'Reminds you to export an encrypted backup',
      importance: Importance.defaultImportance,
    ),
  );

  /// (Re)starts the weekly countdown; first reminder fires in 7 days.
  static Future<void> scheduleBackupReminder() async {
    await _plugin.cancel(id: _backupId);
    await _plugin.periodicallyShow(
      id: _backupId,
      title: 'Back up Silent Wallet',
      body: 'Your data only lives on this phone. Export a backup now.',
      repeatInterval: RepeatInterval.weekly,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelBackupReminder() => _plugin.cancel(id: _backupId);
}
