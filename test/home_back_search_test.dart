import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/back_guard.dart';
import 'package:silentwallet/screens/home.dart';
import 'package:silentwallet/screens/tx_list.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

/// Records the app-exit request instead of really closing the test.
class _Exit {
  int calls = 0;
}

Future<_Exit> _mockSystemExit(WidgetTester t) async {
  final exit = _Exit();
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') exit.calls++;
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return exit;
}

Future<void> _back(WidgetTester t) async {
  await t.binding.handlePopRoute();
  await t.pumpAndSettle();
}

int _tab(WidgetTester t) => t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

Future<void> _pumpHome(WidgetTester t, {List<Tx> txs = const []}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  final repo = FakeRepo(txs: txs)
    ..accounts = sampleAccounts()
    ..categories = sampleCategories()
    ..hasData = txs.isNotEmpty;
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(393, 851);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Settings>.value(value: settings),
      ChangeNotifierProvider<Repo>.value(value: repo),
      ChangeNotifierProvider<LockController>.value(value: LockController(settings)),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: compactText,
      home: const HomeScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 5);
  final longAgo = DateTime(now.year - 1, 3, 12);

  group('search covers all dates and more than notes', () {
    final txs = [
      sampleTx('1', thisMonth, note: 'Coffee', paise: 12000, categoryId: 'e0'),
      sampleTx('2', longAgo, note: 'Zomato dinner', paise: 45050, categoryId: 'e0'),
      sampleTx('3', longAgo, note: 'Weekly shop', paise: 99900, categoryId: 'e1', accountId: 'a2'),
    ];

    testWidgets('finds a note from another month / year', (t) async {
      await _pumpHome(t, txs: txs);
      expect(find.textContaining('Zomato dinner'), findsNothing); // not in this month's list
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'zomato');
      await t.pumpAndSettle();
      expect(find.textContaining('Zomato dinner'), findsOneWidget);
      expect(find.textContaining('Coffee'), findsNothing);
      expect(find.text('1 result across all dates'), findsOneWidget);
    });

    testWidgets('also matches category, account and amount', (t) async {
      await _pumpHome(t, txs: txs);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      Future<void> search(String q) async {
        await t.enterText(find.byType(TextField), q);
        await t.pumpAndSettle();
      }

      await search('groceries'); // category
      expect(find.textContaining('Weekly shop'), findsOneWidget);
      await search('hdfc'); // account
      expect(find.textContaining('Weekly shop'), findsOneWidget);
      await search('450.50'); // amount
      expect(find.textContaining('Zomato dinner'), findsOneWidget);
      await search('no such thing');
      expect(find.textContaining('No transactions match'), findsOneWidget);
    });

    testWidgets('empty search box offers recent notes to tap', (t) async {
      await _pumpHome(t, txs: txs);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(find.text('Recent notes'), findsOneWidget);
      await t.tap(find.widgetWithText(ActionChip, 'Zomato dinner'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'Zomato dinner');
      expect(find.text('1 result across all dates'), findsOneWidget);
    });
  });

  group('Transactions tab and list icons', () {
    final txs = [sampleTx('1', thisMonth, note: 'Coffee', paise: 12000, categoryId: 'e0')];
    Finder navItem(String label) =>
        find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

    testWidgets('tapping Transactions while searching shows the transaction list', (t) async {
      await _pumpHome(t, txs: txs);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget); // search is open
      await t.tap(navItem('Transactions'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing); // search closed
      expect(find.byTooltip('Search'), findsOneWidget); // normal header
      expect(find.textContaining('Coffee'), findsOneWidget); // the month's list
    });

    testWidgets('coming back to Transactions from another tab also leaves search', (t) async {
      await _pumpHome(t, txs: txs);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await t.tap(navItem('Reports'));
      await t.pumpAndSettle();
      await t.tap(navItem('Transactions'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Coffee'), findsOneWidget);
    });

    testWidgets('search text and filters are cleared when the tab is tapped', (t) async {
      await _pumpHome(t, txs: txs);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'coffee');
      await t.pumpAndSettle();
      await t.tap(navItem('Transactions'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('list category icons match the size used on the Add page', (t) async {
      await _pumpHome(t, txs: txs);
      final row = find.byType(TxTile);
      expect(row, findsOneWidget);
      final icon = t.widget<Icon>(find.descendant(of: row, matching: find.byType(Icon)).first);
      expect(icon.size, kCategoryIconSize);
    });
  });

  group('search filters', () {
    final txs = [
      sampleTx('1', thisMonth, note: 'Coffee', paise: 12000, categoryId: 'e0'),
      sampleTx('2', longAgo, note: 'Zomato dinner', paise: 45050, categoryId: 'e0'),
      sampleTx('3', longAgo, note: 'Weekly shop', paise: 99900, categoryId: 'e1', accountId: 'a2'),
    ];

    Future<void> openSearch(WidgetTester t) async {
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester t) async {
      await t.tap(find.byTooltip('Filters'));
      await t.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
    }

    Future<void> apply(WidgetTester t) async {
      await t.tap(find.byKey(const Key('filter-apply')));
      await t.pumpAndSettle();
    }

    Future<void> pick(WidgetTester t, String dropdownKey, String item) async {
      await t.tap(find.byKey(Key(dropdownKey)));
      await t.pumpAndSettle();
      await t.tap(find.text(item).last);
      await t.pumpAndSettle();
    }

    testWidgets('filters alone (no search text) list matching transactions', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await pick(t, 'filter-account', 'HDFC Savings');
      await apply(t);
      expect(find.textContaining('Weekly shop'), findsOneWidget);
      expect(find.textContaining('Zomato dinner'), findsNothing);
      expect(find.byKey(const Key('chip-account')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('chip-account')), matching: find.text('HDFC Savings')), findsOneWidget);
      expect(find.text('1 result across all dates'), findsOneWidget);
    });

    testWidgets('category filter', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await pick(t, 'filter-category', 'Food & Dining');
      await apply(t);
      expect(find.textContaining('Coffee'), findsOneWidget);
      expect(find.textContaining('Zomato dinner'), findsOneWidget);
      expect(find.textContaining('Weekly shop'), findsNothing);
      expect(find.text('2 results across all dates'), findsOneWidget);
    });

    testWidgets('amount range (min and max)', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await t.enterText(find.byKey(const Key('filter-min')), '100');
      await t.enterText(find.byKey(const Key('filter-max')), '500');
      await apply(t);
      expect(find.textContaining('Coffee'), findsOneWidget); // 120
      expect(find.textContaining('Zomato dinner'), findsOneWidget); // 450.50
      expect(find.textContaining('Weekly shop'), findsNothing); // 999
      expect(find.descendant(of: find.byKey(const Key('chip-amount')), matching: find.text('₹100 – ₹500')), findsOneWidget);
    });

    testWidgets('min only and max only', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await t.enterText(find.byKey(const Key('filter-min')), '500');
      await apply(t);
      expect(find.textContaining('Weekly shop'), findsOneWidget);
      expect(find.textContaining('Coffee'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('chip-amount')), matching: find.text('≥ ₹500')), findsOneWidget);
      await openSheet(t);
      await t.tap(find.byKey(const Key('filter-reset')));
      await t.pump();
      await t.enterText(find.byKey(const Key('filter-max')), '200');
      await apply(t);
      expect(find.textContaining('Coffee'), findsOneWidget);
      expect(find.textContaining('Weekly shop'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('chip-amount')), matching: find.text('≤ ₹200')), findsOneWidget);
    });

    testWidgets('a reversed range is swapped', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await t.enterText(find.byKey(const Key('filter-min')), '500');
      await t.enterText(find.byKey(const Key('filter-max')), '100');
      await apply(t);
      expect(find.descendant(of: find.byKey(const Key('chip-amount')), matching: find.text('₹100 – ₹500')), findsOneWidget);
      expect(find.textContaining('Coffee'), findsOneWidget);
    });

    testWidgets('time period: this month / last month / this year', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await t.tap(find.byKey(const Key('filter-period-month')));
      await t.pump();
      await apply(t);
      expect(find.textContaining('Coffee'), findsOneWidget);
      expect(find.textContaining('Zomato dinner'), findsNothing);
      expect(find.text('1 result'), findsOneWidget); // no "across all dates" when a period is set
      expect(find.descendant(of: find.byKey(const Key('chip-period')), matching: find.text('This month')), findsOneWidget);

      await openSheet(t);
      await t.tap(find.byKey(const Key('filter-period-last')));
      await t.pump();
      await apply(t);
      expect(find.textContaining('Coffee'), findsNothing);
      expect(find.text('No transactions match these filters.'), findsOneWidget);

      await openSheet(t);
      await t.tap(find.byKey(const Key('filter-period-year')));
      await t.pump();
      await apply(t);
      expect(find.textContaining('Coffee'), findsOneWidget);
      expect(find.textContaining('Zomato dinner'), findsNothing); // last year
    });

    testWidgets('filters combine with the search text', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await t.enterText(find.byType(TextField), 'zomato');
      await t.pumpAndSettle();
      expect(find.textContaining('Zomato dinner'), findsOneWidget);
      await openSheet(t);
      await pick(t, 'filter-account', 'HDFC Savings');
      await apply(t);
      expect(find.textContaining('Zomato dinner'), findsNothing); // paid from Cash, not HDFC
      expect(find.textContaining('No transactions match "zomato"'), findsOneWidget);
    });

    testWidgets('chips can be removed one by one or all at once', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await pick(t, 'filter-account', 'Cash');
      await t.enterText(find.byKey(const Key('filter-min')), '100');
      await apply(t);
      expect(find.byKey(const Key('chip-account')), findsOneWidget);
      expect(find.byKey(const Key('chip-amount')), findsOneWidget);
      // remove the account chip only
      await t.tap(find.descendant(of: find.byKey(const Key('chip-account')), matching: find.byType(Icon)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chip-account')), findsNothing);
      expect(find.byKey(const Key('chip-amount')), findsOneWidget);
      // clear everything: back to the recent-notes screen
      await t.tap(find.byKey(const Key('chip-clear-all')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('chip-amount')), findsNothing);
      expect(find.text('Recent notes'), findsOneWidget);
    });

    testWidgets('the Filters button shows a badge while filters are active', (t) async {
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      Badge badge() => t.widget<Badge>(find.descendant(of: find.byTooltip('Filters'), matching: find.byType(Badge)));
      expect(badge().isLabelVisible, isFalse);
      await openSheet(t);
      await t.enterText(find.byKey(const Key('filter-min')), '1');
      await apply(t);
      expect(badge().isLabelVisible, isTrue);
    });

    testWidgets('Reset clears the sheet; closing search drops the filters', (t) async {
      final exit = await _mockSystemExit(t);
      await _pumpHome(t, txs: txs);
      await openSearch(t);
      await openSheet(t);
      await t.enterText(find.byKey(const Key('filter-min')), '100');
      await t.tap(find.byKey(const Key('filter-reset')));
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('filter-min'))).controller!.text, isEmpty);
      await t.enterText(find.byKey(const Key('filter-min')), '100');
      await apply(t);
      expect(find.byKey(const Key('chip-amount')), findsOneWidget);
      await _back(t); // back gesture closes the search...
      expect(find.byType(TextField), findsNothing);
      expect(exit.calls, 0);
      await openSearch(t); // ...and reopening starts clean
      expect(find.byKey(const Key('chip-amount')), findsNothing);
      expect(find.text('Recent notes'), findsOneWidget);
    });
  });

  group('back gesture', () {
    testWidgets('closes the search box instead of leaving the app', (t) async {
      final exit = await _mockSystemExit(t);
      await _pumpHome(t);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await _back(t);
      expect(find.byType(TextField), findsNothing); // search closed
      expect(find.byTooltip('Search'), findsOneWidget); // normal Transactions header
      expect(find.text('Press back again to exit'), findsNothing);
      expect(exit.calls, 0);
      expect(_tab(t), 0);
    });

    testWidgets('closing search clears the typed text', (t) async {
      await _mockSystemExit(t);
      await _pumpHome(t, txs: [sampleTx('1', DateTime.now(), note: 'Coffee')]);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'coffee');
      await t.pumpAndSettle();
      await _back(t);
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('from another tab goes back to Transactions', (t) async {
      final exit = await _mockSystemExit(t);
      await _pumpHome(t);
      await t.tap(find.text('Reports'));
      await t.pumpAndSettle();
      expect(_tab(t), 1);
      await _back(t);
      expect(_tab(t), 0);
      expect(exit.calls, 0);
      await t.tap(find.text('Accounts'));
      await t.pumpAndSettle();
      await _back(t);
      expect(_tab(t), 0);
      expect(exit.calls, 0);
    });

    testWidgets('on Transactions it takes two back presses to exit', (t) async {
      final exit = await _mockSystemExit(t);
      await _pumpHome(t);
      await _back(t);
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(exit.calls, 0);
      await _back(t);
      expect(exit.calls, 1);
    });

    testWidgets('a handled back resets the double-press timer', (t) async {
      final exit = await _mockSystemExit(t);
      await _pumpHome(t);
      await _back(t); // 1st press: toast
      await t.tap(find.byTooltip('Search'));
      await t.pumpAndSettle();
      await _back(t); // closes search
      await _back(t); // starts the double-press again, must NOT exit
      expect(exit.calls, 0);
      expect(find.text('Press back again to exit'), findsOneWidget);
    });
  });

  group('BackGuard', () {
    testWidgets('a second press after the window expires does not exit', (t) async {
      var exited = 0;
      await t.pumpWidget(MaterialApp(
        home: BackGuard(
          window: const Duration(milliseconds: 100),
          onBack: () => false,
          onExit: () => exited++,
          child: const Scaffold(body: Text('page')),
        ),
      ));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(exited, 0);
      expect(find.text('Press back again to exit'), findsOneWidget);
    });
  });
}
