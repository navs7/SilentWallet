import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/tx_edit.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

const _defaultExpense = defaultExpenseNames;
final _noteField = find.byKey(const Key('note-field'));
final _amountField = find.byKey(const Key('amount-field'));

FakeRepo _repo({int extraCustom = 0, List<Account>? accounts, List<Tx> txs = const []}) {
  final r = FakeRepo(txs: txs);
  r.accounts = accounts ?? sampleAccounts();
  r.categories = sampleCategories(extraCustom: extraCustom);
  return r;
}

Future<void> _pump(WidgetTester t, Size size,
    {double top = 28,
    double bottom = 24,
    int extra = 0,
    List<Account>? accounts,
    List<Tx> txs = const [], Tx? existing}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  final lock = LockController(settings);
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  t.view.padding = FakeViewPadding(top: top, bottom: bottom);
  t.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    t.view.resetPadding();
    t.view.resetViewPadding();
  });
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Repo>.value(
          value: _repo(extraCustom: extra, accounts: accounts, txs: txs)),
      ChangeNotifierProvider<LockController>.value(value: lock),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.light).copyWith(
        textTheme: buildTheme(Brightness.light).textTheme.apply(fontFamily: 'Roboto'),
      ),
      builder: compactText,
      home: TxEditScreen(existing: existing),
    ),
  ));
  await t.pumpAndSettle();
}

/// Flutter tests draw text with a placeholder font whose letters are as wide as
/// they are tall. Load the real Roboto so tag widths match a phone.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/dev/flutter';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  final loader = FontLoader('Roboto');
  for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final f = File('${dir.path}/$name');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);

  // name, size, status-bar, nav-bar
  const phones = <(String, Size, double, double)>[
    ('compact 360x640', Size(360, 640), 28.0, 24.0),
    ('common 393x851', Size(393, 851), 32.0, 24.0),
    ('tall 412x915', Size(412, 915), 36.0, 40.0),
    ('large-font-ish narrow 340x700', Size(340, 700), 28.0, 24.0),
  ];

  for (final p in phones) {
    testWidgets('fits without scrolling or overflow on ${p.$1}', (t) async {
      await _pump(t, p.$2, top: p.$3, bottom: p.$4);
      expect(tester(t), isNull); // no framework exceptions (e.g. overflow)
      expect(_pageScrollExtent(t), 0, reason: 'page must not scroll');
      expect(find.byType(SingleChildScrollView), findsOneWidget); // just the page shell
      // the note field is on the page, fully visible
      final note = _noteField;
      expect(note, findsOneWidget);
      expect(t.getRect(note).bottom, lessThanOrEqualTo(p.$2.height - p.$4));
      expect(find.text('Add a note'), findsOneWidget);
      // clear gap between the Account field and the first category tag
      final gap = t.getRect(find.text(_defaultExpense.first)).top -
          t.getRect(find.byType(DropdownButtonFormField<String>)).bottom;
      expect(gap, greaterThanOrEqualTo(16), reason: 'account/category spacing');
      // every default category is on screen, inside the viewport
      for (final name in _defaultExpense) {
        final f = find.text(name);
        expect(f, findsOneWidget, reason: name);
        final r = t.getRect(f);
        expect(r.bottom, lessThanOrEqualTo(p.$2.height - p.$4), reason: '$name below screen');
        expect(r.right, lessThanOrEqualTo(p.$2.width), reason: '$name past right edge');
      }
      // the Save button is visible
      expect(t.getRect(find.text('Save')).bottom, lessThanOrEqualTo(p.$2.height - p.$4));
    });
  }

  testWidgets('income shows its own categories, transfer shows none', (t) async {
    await _pump(t, const Size(393, 851));
    await t.tap(find.text('Income'));
    await t.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    await t.tap(find.text('Transfer'));
    await t.pumpAndSettle();
    expect(find.text('Salary'), findsNothing);
    expect(find.text('Moves money between your accounts'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
  });

  testWidgets('typing a note: keyboard opens, page scrolls, field stays reachable', (t) async {
    await _pump(t, const Size(393, 851));
    expect(_pageScrollExtent(t), 0);
    t.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(t.view.resetViewInsets);
    await t.tap(_noteField);
    await t.pumpAndSettle();
    expect(tester(t), isNull);
    await t.enterText(_noteField, 'Dinner with friends');
    await t.pumpAndSettle();
    expect(find.text('Dinner with friends'), findsOneWidget);
    expect(_pageScrollExtent(t), greaterThan(0)); // keyboard => scrollable
    // the note field is above the keyboard
    expect(t.getRect(_noteField).bottom, lessThanOrEqualTo(851 - 320));
    // closing the keyboard restores the fixed, non-scrolling page
    t.view.viewInsets = FakeViewPadding.zero;
    await t.pumpAndSettle();
    expect(_pageScrollExtent(t), 0);
    expect(find.text('Dinner with friends'), findsOneWidget);
  });

  testWidgets('note suggestions come from earlier notes and appear above the field', (t) async {
    final txs = [
      sampleTx('1', DateTime(2026, 3, 1), note: 'Zomato dinner', categoryId: 'e0'),
      sampleTx('2', DateTime(2026, 3, 2), note: 'Zomato dinner', categoryId: 'e0'),
      sampleTx('3', DateTime(2026, 3, 3), note: 'Zomato lunch', categoryId: 'e0'),
      sampleTx('4', DateTime(2026, 3, 4), note: 'Uber ride', categoryId: 'e3'),
    ];
    await _pump(t, const Size(393, 851), txs: txs);
    t.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(t.view.resetViewInsets);
    // focusing the empty field lists recent notes
    await t.tap(_noteField);
    await t.pumpAndSettle();
    expect(tester(t), isNull);
    expect(find.text('Uber ride'), findsOneWidget);
    // typing narrows the list; most used first
    await t.enterText(_noteField, 'zom');
    await t.pumpAndSettle();
    expect(find.text('Zomato dinner'), findsOneWidget);
    expect(find.text('Zomato lunch'), findsOneWidget);
    expect(find.text('Uber ride'), findsNothing);
    expect(t.getRect(find.text('Zomato dinner')).bottom,
        lessThan(t.getRect(_noteField).top)); // above the field
    // choosing one fills the note
    await t.tap(find.text('Zomato dinner'));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(_noteField);
    expect(field.controller!.text, 'Zomato dinner');
    expect(find.text('Zomato lunch'), findsNothing); // list closed
  });

  testWidgets('no suggestions when there is no history yet', (t) async {
    await _pump(t, const Size(393, 851));
    await t.tap(_noteField);
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.history), findsNothing);
  });

  testWidgets('new transactions start on the default account', (t) async {
    final accounts = [
      Account(id: 'a0', name: 'Axis', type: 'Bank'), // sorts first alphabetically
      Account(id: 'a1', name: 'Cash', type: 'Cash', isDefault: true),
    ];
    await _pump(t, const Size(393, 851), accounts: accounts);
    final dd = t.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>));
    expect(dd.initialValue, 'a1');
  });

  testWidgets('without a default the first account is used', (t) async {
    await _pump(t, const Size(393, 851));
    final dd = t.widget<DropdownButtonFormField<String>>(find.byType(DropdownButtonFormField<String>));
    expect(dd.initialValue, 'a1'); // Cash, first in the sample list
  });

  testWidgets('amount uses the numeric keyboard, notes the normal one; no on-screen pad', (t) async {
    await _pump(t, const Size(393, 851));
    final amount = t.widget<TextField>(_amountField);
    expect(amount.keyboardType, const TextInputType.numberWithOptions(decimal: true));
    final note = t.widget<TextField>(_noteField);
    expect(note.keyboardType, TextInputType.text);
    expect(find.byIcon(Icons.backspace_outlined), findsNothing); // old pad is gone
    expect(find.text('7'), findsNothing);
  });

  testWidgets('amount accepts only a valid amount', (t) async {
    await _pump(t, const Size(393, 851));
    Future<String> type(String v) async {
      await t.enterText(_amountField, v);
      await t.pump();
      return t.widget<TextField>(_amountField).controller!.text;
    }

    expect(await type('1234.5'), '1234.5');
    expect(await type('1234.567'), '1234.5'); // 3rd decimal rejected
    expect(await type('12a'), '1234.5'); // letters rejected
    expect(await type('1.2.3'), '1234.5'); // second dot rejected
    expect(await type('150,75'), '150.75'); // comma keyboards: becomes the point
    expect(await type('1234567890'), '150.75'); // too many digits
  });

  testWidgets('a new transaction focuses the amount; editing one does not', (t) async {
    await _pump(t, const Size(393, 851));
    expect(t.widget<TextField>(_amountField).focusNode!.hasFocus, isTrue);
    await t.pumpWidget(const SizedBox());
    await _pump(t, const Size(393, 851),
        existing: sampleTx('9', DateTime(2026, 3, 1), paise: 25050, note: 'Taxi'));
    expect(t.widget<TextField>(_amountField).controller!.text, '250.5');
    expect(t.widget<TextField>(_amountField).focusNode!.hasFocus, isFalse);
    expect(t.widget<TextField>(_noteField).controller!.text, 'Taxi');
  });

  testWidgets('suggestions are plain text (no usage counts) in a fixed, scrollable list', (t) async {
    final txs = [
      for (var i = 0; i < 25; i++)
        sampleTx('n$i', DateTime(2026, 1, 1 + i), note: 'Note number ${i.toString().padLeft(2, '0')}'),
      // used several times: must NOT show a count
      sampleTx('r1', DateTime(2026, 2, 10), note: 'Repeat note'),
      sampleTx('r2', DateTime(2026, 2, 11), note: 'Repeat note'),
      sampleTx('r3', DateTime(2026, 2, 12), note: 'Repeat note'),
    ];
    await _pump(t, const Size(393, 851), txs: txs);
    t.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(t.view.resetViewInsets);
    await t.tap(_noteField);
    await t.pumpAndSettle();
    expect(tester(t), isNull);
    final list = find.byKey(const Key('note-suggestions'));
    expect(list, findsOneWidget);
    expect(find.textContaining(RegExp(r'x\d')), findsNothing);
    expect(find.text('Repeat note'), findsOneWidget);
    expect(t.getSize(list).height, lessThanOrEqualTo(4.5 * 44 + 0.5)); // fixed area
    // the oldest note is not on screen until the list is scrolled
    expect(find.text('Note number 00'), findsNothing);
    await t.drag(list, const Offset(0, -3000));
    await t.pumpAndSettle();
    expect(find.text('Note number 00'), findsOneWidget);
  });

  testWidgets('tags shrink to fit when there are many custom categories', (t) async {
    await _pump(t, const Size(393, 851), extra: 12);
    expect(tester(t), isNull);
    expect(_pageScrollExtent(t), 0);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Custom tag 11'), findsOneWidget);
  });

  testWidgets('absurd category count falls back to scrolling instead of hiding tags', (t) async {
    await _pump(t, const Size(360, 640), extra: 60);
    expect(tester(t), isNull);
    expect(find.byType(SingleChildScrollView), findsNWidgets(2)); // page shell + tag area
  });
}

/// Max scroll extent of the page's outer scroll view (0 = nothing to scroll).
double _pageScrollExtent(WidgetTester t) =>
    t.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;

// Returns any exception the framework caught while building (overflow etc.).
Object? tester(WidgetTester t) => t.takeException();
