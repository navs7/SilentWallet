import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/more_screen.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/reminders.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

class FakeBackend implements ReminderBackend {
  final active = <int, DateTime>{};
  final log = <String>[];

  @override
  Future<void> cancelAll() async {
    active.clear();
    log.add('cancel');
  }

  @override
  Future<void> schedule(int slot, DateTime when) async {
    active[slot] = when;
    log.add('schedule');
  }
}

Future<Settings> _settings([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues({'onboarded': true, ...prefs});
  return Settings.load();
}

void main() {
  group('planReminders', () {
    final morning = DateTime(2026, 10, 15, 10, 0);

    test('before the reminder time: today is included, 30 days in all', () {
      final p = planReminders(now: morning, hour: 20, minute: 0, hasEntryToday: false);
      expect(p.length, 30);
      expect(p.first, DateTime(2026, 10, 15, 20, 0));
      expect(p.last, DateTime(2026, 11, 13, 20, 0));
    });

    test('after the reminder time: starts tomorrow', () {
      final p = planReminders(now: DateTime(2026, 10, 15, 21, 0), hour: 20, minute: 0, hasEntryToday: false);
      expect(p.length, 29);
      expect(p.first, DateTime(2026, 10, 16, 20, 0));
    });

    test('exactly at the reminder time counts as already past', () {
      final p = planReminders(now: DateTime(2026, 10, 15, 20, 0), hour: 20, minute: 0, hasEntryToday: false);
      expect(p.first, DateTime(2026, 10, 16, 20, 0));
    });

    test('an entry added today skips today only', () {
      final p = planReminders(now: morning, hour: 20, minute: 0, hasEntryToday: true);
      expect(p.length, 29);
      expect(p.first, DateTime(2026, 10, 16, 20, 0));
    });

    test('an entry added today changes nothing once the time has passed', () {
      final a = planReminders(now: DateTime(2026, 10, 15, 21, 0), hour: 20, minute: 0, hasEntryToday: true);
      final b = planReminders(now: DateTime(2026, 10, 15, 21, 0), hour: 20, minute: 0, hasEntryToday: false);
      expect(a, b);
    });

    test('custom time, custom length, and month boundaries', () {
      final p = planReminders(now: DateTime(2026, 1, 30, 8, 0), hour: 9, minute: 30, hasEntryToday: false, days: 4);
      expect(p, [
        DateTime(2026, 1, 30, 9, 30),
        DateTime(2026, 1, 31, 9, 30),
        DateTime(2026, 2, 1, 9, 30),
        DateTime(2026, 2, 2, 9, 30),
      ]);
    });

    test('every reminder is on its own day at the chosen time', () {
      final p = planReminders(now: morning, hour: 20, minute: 0, hasEntryToday: false);
      for (var i = 0; i < p.length; i++) {
        expect(p[i], DateTime(2026, 10, 15 + i, 20, 0));
      }
    });
  });

  group('Settings: daily reminder', () {
    test('on by default at 8:00 pm', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      expect(s.dailyReminder, isTrue);
      expect(s.reminderHour, 20);
      expect(s.reminderMinute, 0);
      expect(s.reminderPermissionAsked, isFalse);
    });

    test('saves the switch and the time', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      await s.setDailyReminder(false);
      await s.setReminderTime(21, 15);
      await s.markReminderPermissionAsked();
      final again = await Settings.load();
      expect(again.dailyReminder, isFalse);
      expect(again.reminderHour, 21);
      expect(again.reminderMinute, 15);
      expect(again.reminderPermissionAsked, isTrue);
    });
  });

  group('ReminderService', () {
    final now = DateTime(2026, 10, 15, 10, 0);
    late FakeBackend backend;
    late FakeRepo repo;
    late Settings settings;
    late ReminderService svc;

    Future<void> setup({Map<String, Object> prefs = const {}}) async {
      backend = FakeBackend();
      repo = FakeRepo();
      settings = await _settings(prefs);
      svc = ReminderService(settings, repo,
          backend: backend, clock: () => now, debounce: const Duration(milliseconds: 10));
      addTearDown(svc.dispose);
    }

    Future<void> settle() => Future.delayed(const Duration(milliseconds: 80));

    test('schedules the next 30 days at 8 pm, starting today', () async {
      await setup();
      await svc.refresh();
      expect(backend.active.length, 30);
      expect(backend.active[0], DateTime(2026, 10, 15, 20, 0));
      expect(backend.active[29], DateTime(2026, 11, 13, 20, 0));
    });

    test('skips today when an entry has already been added', () async {
      await setup();
      repo.manualEntryToday = true;
      await svc.refresh();
      expect(backend.active.length, 29);
      expect(backend.active[0], DateTime(2026, 10, 16, 20, 0));
    });

    test('adding an entry removes today\'s reminder; deleting it brings it back', () async {
      await setup();
      await svc.start();
      expect(backend.active[0], DateTime(2026, 10, 15, 20, 0));
      repo.manualEntryToday = true; // the user saved an entry
      repo.notifyListeners();
      await settle();
      expect(backend.active[0], DateTime(2026, 10, 16, 20, 0));
      repo.manualEntryToday = false; // …then deleted it
      repo.notifyListeners();
      await settle();
      expect(backend.active[0], DateTime(2026, 10, 15, 20, 0));
    });

    test('turning the switch off cancels everything; on schedules again', () async {
      await setup();
      await svc.start();
      expect(backend.active, isNotEmpty);
      await settings.setDailyReminder(false);
      await settle();
      expect(backend.active, isEmpty);
      await settings.setDailyReminder(true);
      await settle();
      expect(backend.active.length, 30);
    });

    test('changing the time re-plans at the new time', () async {
      await setup();
      await svc.start();
      await settings.setReminderTime(21, 30);
      await settle();
      expect(backend.active.length, 30);
      for (final t in backend.active.values) {
        expect([t.hour, t.minute], [21, 30]);
      }
    });

    test('a custom saved time is used from the start', () async {
      await setup(prefs: {'reminder_hour': 7, 'reminder_minute': 45});
      await svc.refresh();
      // 7:45 today is already past at 10:00, so it starts tomorrow
      expect(backend.active[0], DateTime(2026, 10, 16, 7, 45));
    });

    test('overlapping refreshes run one after another and never mix', () async {
      await setup();
      await Future.wait([svc.refresh(), svc.refresh(), svc.refresh()]);
      expect(backend.active.length, 30);
      // each run is "cancel" followed by its own 30 schedules
      var i = 0;
      var runs = 0;
      while (i < backend.log.length) {
        expect(backend.log[i], 'cancel');
        i++;
        var n = 0;
        while (i < backend.log.length && backend.log[i] == 'schedule') {
          n++;
          i++;
        }
        expect(n, 30);
        runs++;
      }
      expect(runs, 3);
    });

    test('asks for notification permission once, only after the first run', () async {
      await setup();
      expect(settings.reminderPermissionAsked, isFalse);
      await svc.start();
      expect(settings.reminderPermissionAsked, isTrue);
    });

    test('does not ask before onboarding finishes, nor when the reminder is off', () async {
      await setup(prefs: {'onboarded': false});
      await svc.start();
      expect(settings.reminderPermissionAsked, isFalse);
      final other = await _settings({'daily_reminder': false});
      final s2 = ReminderService(other, FakeRepo(), backend: FakeBackend(), clock: () => now);
      await s2.start();
      expect(other.reminderPermissionAsked, isFalse);
      s2.dispose();
    });

    test('after dispose, changes no longer touch the schedule', () async {
      await setup();
      await svc.start();
      svc.dispose();
      final before = backend.log.length;
      await settings.setDailyReminder(false);
      await settle();
      expect(backend.log.length, before);
    });
  });

  group('More tab: daily reminder', () {
    Future<Settings> pumpMore(WidgetTester t, {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final settings = await Settings.load();
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(393, 1000);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<Settings>.value(value: settings),
          ChangeNotifierProvider<Repo>.value(value: FakeRepo()),
          ChangeNotifierProvider<LockController>.value(value: LockController(settings)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: compactText,
          home: const Scaffold(body: MoreScreen()),
        ),
      ));
      await t.pumpAndSettle();
      return settings;
    }

    final sw = find.byKey(const Key('daily-reminder'));
    final timeTile = find.byKey(const Key('reminder-time'));

    testWidgets('is on by default and says when and when it is skipped', (t) async {
      await pumpMore(t);
      expect(t.widget<SwitchListTile>(sw).value, isTrue);
      expect(find.textContaining('8:00 PM'), findsWidgets);
      expect(find.textContaining('Skipped on days you have already added an entry'), findsOneWidget);
      expect(timeTile, findsOneWidget);
    });

    testWidgets('turning it off hides the time row and saves the choice', (t) async {
      final s = await pumpMore(t);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(s.dailyReminder, isFalse);
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      expect(timeTile, findsNothing);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(s.dailyReminder, isTrue);
      expect(timeTile, findsOneWidget);
    });

    testWidgets('the time row shows the chosen time and opens a time picker', (t) async {
      final s = await pumpMore(t);
      await s.setReminderTime(21, 30);
      await t.pumpAndSettle();
      expect(find.descendant(of: timeTile, matching: find.text('9:30 PM')), findsOneWidget);
      expect(find.textContaining('At 9:30 PM'), findsOneWidget);
      await t.tap(timeTile);
      await t.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget); // the picker dialog
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(s.reminderHour, 21); // unchanged
    });

    testWidgets('an off setting from before is respected', (t) async {
      await pumpMore(t, prefs: {'daily_reminder': false});
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      expect(timeTile, findsNothing);
    });
  });
}
