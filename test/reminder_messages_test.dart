import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/services/reminder_messages.dart';
import 'package:silentwallet/services/reminders.dart';
import 'package:silentwallet/services/settings.dart';

import 'reminders_test.dart' show FakeBackend;
import 'test_support.dart';

/// Day number [d] counted from 1970-01-01 (the same count the app uses).
DateTime _day(int d) => DateTime.utc(1970).add(Duration(days: d));

void main() {
  group('the seven messages', () {
    test('there are seven, all different and not empty', () {
      expect(reminderMessages.length, 7);
      expect(reminderMessages.toSet().length, 7);
      for (final m in reminderMessages) {
        expect(m.trim(), isNotEmpty);
      }
    });

    test('short enough to read at a glance in a notification', () {
      for (final m in reminderMessages) {
        expect(m.length, lessThanOrEqualTo(60), reason: m);
      }
    });
  });

  group('reminderMessageFor', () {
    test('every block of 7 days shows each message exactly once', () {
      for (final seed in [0, 1, 99991]) {
        for (var block = 0; block < 80; block++) {
          final seen = {
            for (var i = 0; i < 7; i++)
              reminderMessageFor(_day(block * 7 + i), seed: seed),
          };
          expect(seen.length, 7, reason: 'seed $seed block $block');
        }
      }
    });

    test('never the same message on two days in a row', () {
      for (final seed in [0, 1, 42, 123456789]) {
        for (var d = 20000; d < 21500; d++) {
          expect(
            reminderMessageFor(_day(d), seed: seed),
            isNot(reminderMessageFor(_day(d + 1), seed: seed)),
            reason: 'seed $seed day $d',
          );
        }
      }
    });

    test('the same day and seed always give the same message', () {
      final day = DateTime(2026, 10, 15);
      final first = reminderMessageFor(day, seed: 7);
      for (var i = 0; i < 5; i++) {
        expect(reminderMessageFor(day, seed: 7), first);
      }
    });

    test('the time of day does not matter, only the date', () {
      expect(
        reminderMessageFor(DateTime(2026, 10, 15, 0, 5), seed: 3),
        reminderMessageFor(DateTime(2026, 10, 15, 23, 55), seed: 3),
      );
    });

    test('the order is shuffled: it changes from one week to the next', () {
      final orders = <String>{};
      for (var block = 100; block < 130; block++) {
        orders.add(
          [
            for (var i = 0; i < 7; i++)
              reminderMessageFor(_day(block * 7 + i), seed: 5),
          ].join('|'),
        );
      }
      expect(orders.length, greaterThan(20)); // almost every week is different
    });

    test('different installs (seeds) get different orders', () {
      List<String> run(int seed) => [
        for (var d = 20000; d < 20070; d++)
          reminderMessageFor(_day(d), seed: seed),
      ];
      expect(run(1), isNot(run(2)));
      expect(run(2), isNot(run(3)));
    });

    test('a 30-day plan uses every message, several times', () {
      final counts = <String, int>{};
      for (var d = 0; d < 30; d++) {
        final m = reminderMessageFor(DateTime(2026, 10, 15 + d), seed: 11);
        counts[m] = (counts[m] ?? 0) + 1;
      }
      expect(counts.length, 7);
      for (final c in counts.values) {
        expect(c, inInclusiveRange(4, 5)); // 30 days = 4 full weeks + 2
      }
    });
  });

  group('the reminder service uses them', () {
    final now = DateTime(2026, 10, 15, 10, 0);

    Future<(ReminderService, FakeBackend, Settings)> make([
      Map<String, Object> prefs = const {},
    ]) async {
      SharedPreferences.setMockInitialValues({'onboarded': true, ...prefs});
      final settings = await Settings.load();
      final backend = FakeBackend();
      final svc = ReminderService(
        settings,
        FakeRepo(),
        backend: backend,
        clock: () => now,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(svc.dispose);
      return (svc, backend, settings);
    }

    test('each scheduled day carries its own message', () async {
      final (svc, backend, settings) = await make({'reminder_seed': 4242});
      await svc.refresh();
      expect(backend.bodies.length, 30);
      for (final slot in backend.active.keys) {
        expect(
          backend.bodies[slot],
          reminderMessageFor(
            backend.active[slot]!,
            seed: settings.reminderSeed,
          ),
        );
      }
      // randomised: not one message repeated for every day, and never twice in a row
      expect(backend.bodies.values.toSet().length, 7);
      for (var i = 1; i < 30; i++) {
        expect(backend.bodies[i], isNot(backend.bodies[i - 1]));
      }
    });

    test('re-planning does not change any day\'s message', () async {
      final (svc, backend, _) = await make({'reminder_seed': 17});
      await svc.refresh();
      final first = Map.of(backend.bodies);
      await svc.refresh();
      await svc.refresh();
      expect(backend.bodies, first);
    });

    test('skipping today does not shift the other days\' messages', () async {
      final (svc, backend, _) = await make({'reminder_seed': 17});
      await svc.refresh();
      final withToday = {
        for (final e in backend.active.entries) e.value: backend.bodies[e.key],
      };
      final repo = (svc.repo as FakeRepo)..manualEntryToday = true;
      expect(repo.manualEntryToday, isTrue);
      await svc.refresh();
      for (final e in backend.active.entries) {
        expect(
          backend.bodies[e.key],
          withToday[e.value],
          reason: 'message for ${e.value}',
        );
      }
    });

    test('starting creates this install\'s seed once and keeps it', () async {
      final (svc, _, settings) = await make();
      expect(settings.reminderSeed, 0);
      await svc.start();
      final seed = settings.reminderSeed;
      expect(seed, isNot(0));
      expect((await Settings.load()).reminderSeed, seed); // saved
      await settings.ensureReminderSeed(); // asking again changes nothing
      expect(settings.reminderSeed, seed);
    });

    test(
      'two installs with different seeds get different message orders',
      () async {
        final (a, backendA, _) = await make({'reminder_seed': 1});
        await a.refresh();
        final (b, backendB, _) = await make({'reminder_seed': 2});
        await b.refresh();
        expect(
          backendA.bodies.values.toList(),
          isNot(backendB.bodies.values.toList()),
        );
      },
    );
  });
}
