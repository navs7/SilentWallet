import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

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
    try {
      final a = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return (await a?.requestNotificationsPermission()) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Whether Android currently lets this app show notifications.
  static Future<bool> notificationsAllowed() async {
    try {
      final a = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return (await a?.areNotificationsEnabled()) ?? true;
    } catch (_) {
      return true;
    }
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

  // ---- daily "add today's entries" reminder (one scheduled per day) ----
  static const _entryBase = 2000;
  static const _entrySlots = 60;

  static const _entryDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'entry_reminder',
      'Daily entry reminder',
      channelDescription: "Reminds you to add today's entries",
      importance: Importance.defaultImportance,
    ),
  );

  static Future<void> cancelEntryReminders() async {
    try {
      for (var i = 0; i < _entrySlots; i++) {
        await _plugin.cancel(id: _entryBase + i);
      }
    } catch (_) {}
  }

  /// Schedules one reminder at the local time [when] (slot 0..59).
  static Future<void> scheduleEntryReminder(int slot, DateTime when) async {
    try {
      await _plugin.zonedSchedule(
        id: _entryBase + slot,
        title: 'Silent Wallet',
        body: 'Anything to add for today? Log your entries before you forget.',
        // an exact instant; the zone only matters for display
        scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
        notificationDetails: _entryDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }
}
