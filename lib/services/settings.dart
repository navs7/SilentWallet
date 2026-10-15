import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  final SharedPreferences _p;
  Settings(this._p);

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  bool get lockEnabled => _p.getBool('lock') ?? false;
  bool get onboarded => _p.getBool('onboarded') ?? false;

  /// Off (the default) blocks screenshots and hides the app in recent apps.
  bool get allowScreenshots => _p.getBool('allow_screenshots') ?? false;

  /// Daily "add today's entries" reminder: on by default, 8:00 pm.
  bool get dailyReminder => _p.getBool('daily_reminder') ?? true;
  int get reminderHour => _p.getInt('reminder_hour') ?? 20;
  int get reminderMinute => _p.getInt('reminder_minute') ?? 0;
  bool get reminderPermissionAsked => _p.getBool('reminder_asked') ?? false;
  bool get weeklyReminder => _p.getBool('reminder') ?? true;
  DateTime? get lastBackup {
    final v = _p.getInt('last_backup');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  ThemeMode get themeMode => switch (_p.getString('theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setLock(bool v) async {
    await _p.setBool('lock', v);
    notifyListeners();
  }

  Future<void> setAllowScreenshots(bool v) async {
    await _p.setBool('allow_screenshots', v);
    notifyListeners();
  }

  Future<void> setDailyReminder(bool v) async {
    await _p.setBool('daily_reminder', v);
    notifyListeners();
  }

  Future<void> setReminderTime(int hour, int minute) async {
    await _p.setInt('reminder_hour', hour);
    await _p.setInt('reminder_minute', minute);
    notifyListeners();
  }

  Future<void> markReminderPermissionAsked() async {
    await _p.setBool('reminder_asked', true);
  }

  Future<void> setOnboarded() async {
    await _p.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> setWeeklyReminder(bool v) async {
    await _p.setBool('reminder', v);
    notifyListeners();
  }

  Future<void> markBackedUp() async {
    await _p.setInt('last_backup', DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    await _p.setString('theme', m.name);
    notifyListeners();
  }

  /// True when the user should be nudged to export a backup.
  bool backupDue(bool hasData) {
    if (!hasData) return false;
    final last = lastBackup;
    return last == null || DateTime.now().difference(last).inDays >= 7;
  }
}
