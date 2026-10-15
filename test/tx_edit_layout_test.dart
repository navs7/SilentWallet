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
    List<Tx> txs = const []}) async {
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
      home: const TxEditScreen(),
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
      final note = find.byType(TextField);
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
    await t.tap(find.byType(TextField));
    await t.pumpAndSettle();
    expect(tester(t), isNull);
    await t.enterText(find.byType(TextField), 'Dinner with friends');
    await t.pumpAndSettle();
    expect(find.text('Dinner with friends'), findsOneWidget);
    expect(_pageScrollExtent(t), greaterThan(0)); // keyboard => scrollable
    // the note field is above the keyboard
    expect(t.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(851 - 320));
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
    await t.tap(find.byType(TextField));
    await t.pumpAndSettle();
    expect(tester(t), isNull);
    expect(find.text('Uber ride'), findsOneWidget);
    // typing narrows the list; most used first
    await t.enterText(find.byType(TextField), 'zom');
    await t.pumpAndSettle();
    expect(find.text('Zomato dinner'), findsOneWidget);
    expect(find.text('Zomato lunch'), findsOneWidget);
    expect(find.text('Uber ride'), findsNothing);
    expect(t.getRect(find.text('Zomato dinner')).bottom,
        lessThan(t.getRect(find.byType(TextField)).top)); // above the field
    // choosing one fills the note
    await t.tap(find.text('Zomato dinner'));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Zomato dinner');
    expect(find.text('Zomato lunch'), findsNothing); // list closed
  });

  testWidgets('no suggestions when there is no history yet', (t) async {
    await _pump(t, const Size(393, 851));
    await t.tap(find.byType(TextField));
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

  testWidgets('number pad builds the amount with two decimals max', (t) async {
    await _pump(t, const Size(393, 851));
    for (final k in ['1', '2', '3', '4', '.', '5', '6', '7']) {
      await t.tap(find.text(k).first);
    }
    await t.pump();
    expect(find.text('₹ 1,234.56'), findsOneWidget); // 3rd decimal ignored
    await t.tap(find.byIcon(Icons.backspace_outlined));
    await t.pump();
    expect(find.text('₹ 1,234.5'), findsOneWidget);
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
