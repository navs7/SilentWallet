import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/core/search.dart';
import 'package:silentwallet/screens/home.dart';
import 'package:silentwallet/screens/tx_edit.dart';
import 'package:silentwallet/services/backup.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

final _noteField = find.byKey(const Key('note-field'));
final _commentField = find.byKey(const Key('comment-field'));
final _copyButton = find.byKey(const Key('copy-button'));
final _deleteButton = find.byKey(const Key('delete-button'));
final _amountField = find.byKey(const Key('amount-field'));

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

Tx _original({
  String id = 'orig',
  int paise = 25050,
  String note = 'Dinner',
  String comment = 'with the team, split later',
  String? receipt,
  String? recurringId,
}) => Tx(
  id: id,
  type: TxType.expense,
  amount: paise,
  accountId: 'a2',
  categoryId: 'e1',
  note: note,
  comment: comment,
  date: DateTime(2026, 3, 1, 19, 30),
  receipt: receipt,
  recurringId: recurringId,
);

FakeRepo _repo({List<Tx> txs = const []}) {
  final r = FakeRepo(txs: txs);
  r.accounts = sampleAccounts();
  r.categories = sampleCategories();
  return r;
}

Future<FakeRepo> _pump(
  WidgetTester t,
  Size size, {
  Tx? existing,
  FakeRepo? repo,
  double top = 28,
  double bottom = 24,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  final r = repo ?? _repo(txs: existing == null ? const [] : [existing]);
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  t.view.padding = FakeViewPadding(top: top, bottom: bottom);
  t.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.view.resetPadding();
    t.view.resetViewPadding();
    t.view.resetViewInsets();
  });
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Repo>.value(value: r),
        ChangeNotifierProvider<LockController>.value(
          value: LockController(settings),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: compactText,
        initialRoute: '/add',
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/add': (_) => TxEditScreen(existing: existing),
        },
      ),
    ),
  );
  await t.pumpAndSettle();
  return r;
}

/// New entry: type a simple amount and press Done (moves on to the note).
Future<void> _toNote(WidgetTester t, [String amount = '5']) async {
  for (final k in amount.split('')) {
    await t.tap(find.byKey(Key('pad-${k == '.' ? 'dot' : k}')));
  }
  await t.tap(find.byKey(const Key('pad-done')));
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) async {
  await t.tap(find.text('Save'));
  await t.pumpAndSettle();
}

String _text(WidgetTester t, Finder f) =>
    t.widget<TextField>(f).controller!.text;

void main() {
  setUpAll(loadAppFonts);

  // ---------------------------------------------------------------- model
  group('Tx.comment', () {
    Tx tx({String comment = ''}) => Tx(
      id: 'x',
      type: TxType.expense,
      amount: 100,
      accountId: 'a1',
      date: DateTime(2026),
      comment: comment,
    );

    test('defaults to empty', () {
      expect(
        Tx(
          id: 'x',
          type: TxType.expense,
          amount: 1,
          accountId: 'a',
          date: DateTime(2026),
        ).comment,
        '',
      );
    });

    test('is saved and read back', () {
      final back = Tx.fromMap(
        tx(comment: 'line one\nline two, "quoted"').toMap(),
      );
      expect(back.comment, 'line one\nline two, "quoted"');
    });

    test('data from before comments existed loads with an empty comment', () {
      final m = tx().toMap()..remove('comment');
      expect(Tx.fromMap(m).comment, '');
      final n = tx().toMap()..['comment'] = null;
      expect(Tx.fromMap(n).comment, '');
    });

    test('is kept separate from the note', () {
      final t = Tx(
        id: 'x',
        type: TxType.expense,
        amount: 1,
        accountId: 'a',
        date: DateTime(2026),
        note: 'Short',
        comment: 'Long text',
      );
      final m = t.toMap();
      expect(m['note'], 'Short');
      expect(m['comment'], 'Long text');
    });
  });

  group('searching and exporting comments', () {
    test('search finds words in the comment, together with other words', () {
      final t = _original();
      expect(txMatches(t, 'split'), isTrue);
      expect(txMatches(t, 'team'), isTrue);
      expect(txMatches(t, 'dinner team'), isTrue); // note + comment
      expect(txMatches(t, 'dinner refund'), isFalse);
    });

    test('CSV has a Comment column and quotes awkward text', () async {
      final repo = _repo(
        txs: [
          _original(comment: 'split, then "settle"\nnext week'),
          _original(id: 'plain', comment: ''),
        ],
      );
      final csv = await BackupService.csv(repo);
      final lines = csv.split('\n');
      expect(
        lines.first,
        'Date,Type,Amount (INR),Account,To Account,Category,Note,Comment',
      );
      expect(csv, contains('"split, then ""settle""\nnext week"'));
      expect(
        csv,
        contains('Dinner,\n'),
      ); // an empty comment is just an empty last column
    });
  });

  // ------------------------------------------------------- the comment box
  group('Comment box on the Add page', () {
    testWidgets(
      'is a visible box with a hint, up to three lines, below the note',
      (t) async {
        await _pump(t, const Size(393, 851));
        expect(_commentField, findsNothing); // the keypad is showing first
        await _toNote(t);
        expect(_commentField, findsOneWidget);
        expect(find.text('Add a comment (optional)'), findsOneWidget);
        final f = t.widget<TextField>(_commentField);
        expect(f.minLines, 1);
        expect(f.maxLines, 3);
        expect(f.keyboardType, TextInputType.multiline);
        expect(
          t.getRect(_commentField).top,
          greaterThan(t.getRect(_noteField).bottom),
        );
        expect(
          t.getRect(find.text('Save')).top,
          greaterThan(t.getRect(_commentField).bottom),
        );
      },
    );

    testWidgets(
      'what you type is saved with the entry, trimmed, apart from the note',
      (t) async {
        final repo = await _pump(t, const Size(393, 851));
        await _toNote(t, '120');
        await t.enterText(_noteField, 'Lunch');
        await t.enterText(
          _commentField,
          '  with Asha, she pays back on Friday  ',
        );
        await t.pump();
        await _save(t);
        final tx = repo.saved.single;
        expect(tx.note, 'Lunch');
        expect(tx.comment, 'with Asha, she pays back on Friday');
      },
    );

    testWidgets('left empty it saves as an empty comment', (t) async {
      final repo = await _pump(t, const Size(393, 851));
      await _toNote(t, '30');
      await _save(t);
      expect(repo.saved.single.comment, '');
    });

    testWidgets('a multi-line comment is kept as typed', (t) async {
      final repo = await _pump(t, const Size(393, 851));
      await _toNote(t, '30');
      await t.enterText(_commentField, 'first line\nsecond line\nthird line');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await _save(t);
      expect(repo.saved.single.comment, 'first line\nsecond line\nthird line');
    });

    testWidgets('editing an entry shows its comment and can change it', (
      t,
    ) async {
      final orig = _original();
      final repo = await _pump(t, const Size(393, 851), existing: orig);
      expect(_text(t, _commentField), 'with the team, split later');
      expect(_text(t, _noteField), 'Dinner');
      await t.enterText(_commentField, 'settled');
      await t.pump();
      await _save(t);
      expect(repo.saved.single.id, orig.id); // an edit, not a new entry
      expect(repo.saved.single.comment, 'settled');
      expect(repo.saved.single.note, 'Dinner');
    });

    testWidgets('the note\'s Next key moves on to the comment', (t) async {
      await _pump(t, const Size(393, 851));
      await _toNote(t);
      expect(
        t.widget<TextField>(_noteField).textInputAction,
        TextInputAction.next,
      );
      await t.tap(_noteField);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(_noteField).focusNode!.hasFocus, isTrue);
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(_commentField).focusNode!.hasFocus, isTrue);
      expect(t.widget<TextField>(_noteField).focusNode!.hasFocus, isFalse);
    });

    testWidgets(
      'typing a comment keeps note, comment and Save above the keyboard',
      (t) async {
        await _pump(t, const Size(360, 640));
        await _toNote(t);
        await t.tap(_commentField);
        await t.pumpAndSettle();
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.widget<TextField>(_commentField).focusNode!.hasFocus, isTrue);
        final keyboardTop = 640.0 - 300;
        for (final f in [_noteField, _commentField, find.text('Save')]) {
          expect(
            t.getRect(f).bottom,
            lessThanOrEqualTo(keyboardTop),
            reason: '$f hidden by the keyboard',
          );
          expect(t.getRect(f).top, greaterThanOrEqualTo(0));
        }
      },
    );

    for (final p in const [
      ('compact 360x640', Size(360, 640), 28.0, 24.0),
      ('common 393x851', Size(393, 851), 32.0, 24.0),
      ('tall 412x915', Size(412, 915), 36.0, 40.0),
      ('narrow 340x700', Size(340, 700), 28.0, 24.0),
    ]) {
      testWidgets('fits without overflow, even with a long comment: ${p.$1}', (
        t,
      ) async {
        await _pump(t, p.$2, top: p.$3, bottom: p.$4);
        await _toNote(t);
        await t.enterText(_commentField, 'one\ntwo\nthree');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final limit = p.$2.height - p.$4;
        for (final f in [
          _noteField,
          _commentField,
          find.text('Save'),
          find.byKey(const Key('repeat-button')),
        ]) {
          expect(f, findsOneWidget);
          expect(t.getRect(f).bottom, lessThanOrEqualTo(limit));
        }
        for (final name in defaultExpenseNames) {
          expect(
            find.text(name),
            findsOneWidget,
            reason: name,
          ); // every category still reachable
        }
      });
    }
  });

  // ---------------------------------------------------------------- Copy
  group('Copy button', () {
    testWidgets('next to Delete when editing, and nowhere else', (t) async {
      await _pump(t, const Size(393, 851), existing: _original());
      expect(_copyButton, findsOneWidget);
      expect(_deleteButton, findsOneWidget);
      expect(find.byTooltip('Copy transaction'), findsOneWidget);
      // the two buttons sit side by side in the app bar, Copy first
      expect(
        t.getRect(_copyButton).right,
        lessThanOrEqualTo(t.getRect(_deleteButton).left + 0.5),
      );
      expect(
        (t.getRect(_copyButton).center.dy - t.getRect(_deleteButton).center.dy)
            .abs(),
        lessThan(1),
      );
      // a brand-new entry has neither
      await t.pumpWidget(const SizedBox());
      await _pump(t, const Size(393, 851));
      expect(_copyButton, findsNothing);
      expect(_deleteButton, findsNothing);
    });

    testWidgets(
      'opens a new "Copy transaction" page filled in from the entry',
      (t) async {
        await _pump(t, const Size(393, 851), existing: _original());
        expect(find.text('Edit transaction'), findsOneWidget);
        await t.tap(_copyButton);
        await t.pumpAndSettle();
        expect(
          find.text('Copy transaction'),
          findsWidgets,
        ); // title (and the tooltip text isn't built)
        expect(find.text('Edit transaction'), findsNothing);
        expect(_text(t, _amountField), '250.5');
        expect(_text(t, _noteField), 'Dinner');
        expect(_text(t, _commentField), 'with the team, split later');
        expect(
          find.text('Today'),
          findsOneWidget,
        ); // dated today, not the old date
        expect(
          find.text('Save'),
          findsOneWidget,
        ); // keypad closed: ready to save
        expect(find.byKey(const Key('pad-done')), findsNothing);
        expect(_copyButton, findsNothing); // it is a new entry now
        expect(_deleteButton, findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'saving creates a NEW entry with the same details; the original stays',
      (t) async {
        final orig = _original();
        final repo = await _pump(t, const Size(393, 851), existing: orig);
        await t.tap(_copyButton);
        await t.pumpAndSettle();
        await _save(t);
        expect(repo.saved.length, 1); // only the copy was written
        final copy = repo.saved.single;
        expect(copy.id, isNot(orig.id));
        expect(copy.type, orig.type);
        expect(copy.amount, orig.amount);
        expect(copy.accountId, orig.accountId);
        expect(copy.categoryId, orig.categoryId);
        expect(copy.note, orig.note);
        expect(copy.comment, orig.comment);
        expect(
          DateTime(copy.date.year, copy.date.month, copy.date.day),
          _today(),
        );
        expect(copy.receipt, isNull);
        expect(copy.recurringId, isNull);
        // both entries exist now and the original is untouched
        expect(repo.txs.length, 2);
        expect(repo.txs.firstWhere((x) => x.id == orig.id).note, 'Dinner');
        expect(
          find.text('home'),
          findsOneWidget,
        ); // back to the list; the old editor is gone
      },
    );

    testWidgets('the copy can be changed before saving', (t) async {
      final repo = await _pump(t, const Size(393, 851), existing: _original());
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await t.enterText(_noteField, 'Dinner again');
      await t.enterText(_commentField, '');
      await t.tap(find.text('Groceries').first, warnIfMissed: false);
      await t.pump();
      await _save(t);
      final copy = repo.saved.single;
      expect(copy.note, 'Dinner again');
      expect(copy.comment, '');
      expect(copy.amount, 25050);
    });

    testWidgets('copies what is on screen, including edits not yet saved', (
      t,
    ) async {
      final repo = await _pump(t, const Size(393, 851), existing: _original());
      await t.enterText(_noteField, 'Brunch');
      await t.enterText(_commentField, 'edited comment');
      await t.pump();
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      expect(_text(t, _noteField), 'Brunch');
      expect(_text(t, _commentField), 'edited comment');
      await _save(t);
      expect(repo.saved.single.note, 'Brunch'); // the copy has the new text
      expect(
        repo.txs.firstWhere((x) => x.id == 'orig').note,
        'Dinner',
      ); // the original was never saved
    });

    testWidgets('a receipt is not copied', (t) async {
      final repo = await _pump(
        t,
        const Size(393, 851),
        existing: _original(receipt: 'r1.enc'),
      );
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await _save(t);
      expect(repo.saved.single.receipt, isNull);
    });

    testWidgets(
      'an entry made by a recurring rule is copied as a plain entry',
      (t) async {
        final repo = await _pump(
          t,
          const Size(393, 851),
          existing: _original(recurringId: 'rule-1'),
        );
        await t.tap(_copyButton);
        await t.pumpAndSettle();
        await _save(t);
        expect(repo.saved.single.recurringId, isNull);
        expect(repo.savedRules, isEmpty);
      },
    );

    testWidgets('a transfer keeps both accounts and has no category', (
      t,
    ) async {
      final orig = Tx(
        id: 'tr',
        type: TxType.transfer,
        amount: 100000,
        accountId: 'a1',
        toAccountId: 'a2',
        note: 'Rent share',
        comment: 'monthly',
        date: DateTime(2026, 3, 1),
      );
      final repo = await _pump(t, const Size(393, 851), existing: orig);
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await _save(t);
      final copy = repo.saved.single;
      expect(copy.type, TxType.transfer);
      expect(copy.accountId, 'a1');
      expect(copy.toAccountId, 'a2');
      expect(copy.categoryId, isNull);
      expect(copy.comment, 'monthly');
      expect(copy.id, isNot('tr'));
    });

    testWidgets('an income entry is copied as income', (t) async {
      final orig = Tx(
        id: 'inc',
        type: TxType.income,
        amount: 5000000,
        accountId: 'a1',
        categoryId: 'i1',
        note: 'Salary',
        date: DateTime(2026, 3, 1),
      );
      final repo = await _pump(t, const Size(393, 851), existing: orig);
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await _save(t);
      expect(repo.saved.single.type, TxType.income);
      expect(repo.saved.single.categoryId, 'i1');
      expect(repo.saved.single.amount, 5000000);
    });

    testWidgets('going back from the copy saves nothing', (t) async {
      final repo = await _pump(t, const Size(393, 851), existing: _original());
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(repo.saved, isEmpty);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets(
      'the amount can still be changed on the copy (tap it to open the keypad)',
      (t) async {
        final repo = await _pump(
          t,
          const Size(393, 851),
          existing: _original(),
        );
        await t.tap(_copyButton);
        await t.pumpAndSettle();
        await t.tap(_amountField);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('pad-done')), findsOneWidget);
        await t.tap(find.byKey(const Key('pad-back')));
        await t.tap(find.byKey(const Key('pad-9')));
        await t.tap(find.byKey(const Key('pad-done')));
        await t.pumpAndSettle();
        await _save(t);
        expect(repo.saved.single.amount, 25090); // 250.5 -> 250.9
      },
    );

    testWidgets('a copy is a new entry, so it can be made to repeat', (
      t,
    ) async {
      final repo = await _pump(t, const Size(393, 851), existing: _original());
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('repeat-button')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('repeat-monthly')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('repeat-done')));
      await t.pumpAndSettle();
      await _save(t);
      expect(repo.savedRules.single.frequency, Frequency.monthly);
      expect(repo.saved.single.recurringId, repo.savedRules.single.id);
    });

    testWidgets(
      'an emptied amount copies as an empty amount and must be filled in',
      (t) async {
        final repo = await _pump(
          t,
          const Size(393, 851),
          existing: _original(),
        );
        // clear the amount on the edit page via the keypad
        await t.tap(_amountField);
        await t.pumpAndSettle();
        await t.longPress(find.byKey(const Key('pad-back')));
        await t.tap(find.byKey(const Key('pad-close')));
        await t.pumpAndSettle();
        await t.tap(_copyButton);
        await t.pumpAndSettle();
        expect(_text(t, _amountField), '');
        await _save(t);
        expect(find.text('Enter an amount.'), findsOneWidget);
        expect(repo.saved, isEmpty);
      },
    );

    testWidgets('fits and works on a small phone', (t) async {
      final repo = await _pump(t, const Size(360, 640), existing: _original());
      await t.tap(_copyButton);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await _save(t);
      expect(repo.saved.length, 1);
    });
  });

  // ------------------------------------------------- list + search integration
  group('comments in the transaction list', () {
    Future<void> pumpHome(WidgetTester t, List<Tx> txs) async {
      SharedPreferences.setMockInitialValues({'onboarded': true});
      final settings = await Settings.load();
      final repo = FakeRepo(txs: txs)
        ..accounts = sampleAccounts()
        ..categories = sampleCategories()
        ..hasData = true;
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(393, 851);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<Settings>.value(value: settings),
            ChangeNotifierProvider<Repo>.value(value: repo),
            ChangeNotifierProvider<LockController>.value(
              value: LockController(settings),
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: compactText,
            home: const HomeScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    final now = DateTime.now();
    final day = DateTime(now.year, now.month, 3, 12);
    List<Tx> data() => [
      Tx(
        id: 'c1',
        type: TxType.expense,
        amount: 12000,
        accountId: 'a1',
        categoryId: 'e0',
        note: 'Coffee',
        comment: 'refund pending from Raj',
        date: day,
      ),
      Tx(
        id: 'c2',
        type: TxType.expense,
        amount: 9000,
        accountId: 'a1',
        categoryId: 'e0',
        note: 'Tea',
        date: day.subtract(const Duration(hours: 1)),
      ),
    ];

    testWidgets('only entries with a comment show the comment icon', (t) async {
      await pumpHome(t, data());
      expect(find.byKey(const Key('comment-icon-c1')), findsOneWidget);
      expect(find.byKey(const Key('comment-icon-c2')), findsNothing);
    });

    testWidgets('long-pressing the icon shows the comment', (t) async {
      await pumpHome(t, data());
      await t.longPress(find.byKey(const Key('comment-icon-c1')));
      await t.pumpAndSettle();
      expect(find.text('refund pending from Raj'), findsOneWidget);
    });

    testWidgets('a whitespace-only comment shows no icon', (t) async {
      final d = data();
      d[1].comment = '   ';
      await pumpHome(t, d);
      expect(find.byKey(const Key('comment-icon-c2')), findsNothing);
    });

    testWidgets('searching for a word from a comment finds the entry', (
      t,
    ) async {
      await pumpHome(t, data());
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'refund');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tx-row-c1')), findsOneWidget);
      expect(find.byKey(const Key('tx-row-c2')), findsNothing);
    });
  });
}
