import 'dart:async';

import '../core/repo.dart';
import 'notifications.dart';
import 'settings.dart';

/// The (local) times at which to remind the user: one per day for the next
/// [days] days at [hour]:[minute]. Times already past are skipped, and so is
/// today's reminder when the user has [hasEntryToday] already.
List<DateTime> planReminders({
  required DateTime now,
  required int hour,
  required int minute,
  required bool hasEntryToday,
  int days = 30,
}) {
  final out = <DateTime>[];
  for (var i = 0; i < days; i++) {
    final t = DateTime(now.year, now.month, now.day + i, hour, minute);
    if (!t.isAfter(now)) continue;
    if (i == 0 && hasEntryToday) continue;
    out.add(t);
  }
  return out;
}

/// Where reminders are actually scheduled (the phone's notification system).
abstract class ReminderBackend {
  Future<void> cancelAll();
  Future<void> schedule(int slot, DateTime when);
}

class NotifierBackend implements ReminderBackend {
  @override
  Future<void> cancelAll() => Notifier.cancelEntryReminders();

  @override
  Future<void> schedule(int slot, DateTime when) =>
      Notifier.scheduleEntryReminder(slot, when);
}

/// Keeps the daily "add today's entries" reminders up to date.
///
/// Reminders are scheduled one by one for the next 30 days (all local, no
/// server). They are re-planned whenever the app starts or resumes, when the
/// settings change, and when entries are added or removed, so that a day on
/// which you have already logged something is skipped.
class ReminderService {
  final Settings settings;
  final Repo repo;
  final ReminderBackend backend;
  final DateTime Function() clock;
  final Duration debounce;

  Timer? _timer;
  Future<void> _queue = Future.value();

  ReminderService(
    this.settings,
    this.repo, {
    ReminderBackend? backend,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 1),
  }) : backend = backend ?? NotifierBackend(),
       clock = clock ?? DateTime.now;

  /// Start listening for changes, ask for notification permission once (after
  /// the first run) and plan the reminders.
  Future<void> start() async {
    settings.addListener(_changed);
    repo.addListener(_changed);
    if (settings.onboarded &&
        settings.dailyReminder &&
        !settings.reminderPermissionAsked) {
      await Notifier.requestPermission();
      await settings.markReminderPermissionAsked();
    }
    await refresh();
  }

  void dispose() {
    _timer?.cancel();
    settings.removeListener(_changed);
    repo.removeListener(_changed);
  }

  void _changed() {
    _timer?.cancel();
    _timer = Timer(debounce, refresh);
  }

  /// Re-plan now. Calls are run one after another so they never overlap.
  Future<void> refresh() {
    _queue = _queue.then((_) => _plan()).catchError((_) {});
    return _queue;
  }

  Future<void> _plan() async {
    if (!settings.dailyReminder) {
      await backend.cancelAll();
      return;
    }
    final now = clock();
    final has = await repo.hasManualEntryOn(
      DateTime(now.year, now.month, now.day),
    );
    final plan = planReminders(
      now: now,
      hour: settings.reminderHour,
      minute: settings.reminderMinute,
      hasEntryToday: has,
    );
    await backend.cancelAll();
    for (var i = 0; i < plan.length; i++) {
      await backend.schedule(i, plan[i]);
    }
  }
}
