import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/accounts_screen.dart';
import 'package:silentwallet/screens/categories_screen.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

FakeRepo _repo({int extra = 0, List<Tx> txs = const []}) {
  final r = FakeRepo(txs: txs);
  r.accounts = sampleAccounts();
  r.categories = sampleCategories(extraCustom: extra);
  return r;
}

Future<void> _pump(WidgetTester t, Widget page, FakeRepo repo, {Size size = const Size(393, 851)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ChangeNotifierProvider<Repo>.value(
    value: repo,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: compactText,
      home: Scaffold(body: page),
    ),
  ));
  await t.pumpAndSettle();
}

Finder _chip(String id) => find.byKey(Key('cat-chip-$id'));

void main() {
  group('Accounts tab now also manages categories', () {
    testWidgets('shows the accounts and the categories on one page', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      expect(find.text('Accounts'), findsOneWidget); // section header
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Cash'), findsWidgets); // the account (and its type)
      expect(find.text('HDFC Savings'), findsOneWidget);
      expect(find.text('New account'), findsOneWidget);
      expect(find.text('Expense'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.byKey(const Key('add-category-expense')), findsOneWidget);
      expect(find.byKey(const Key('add-category-income')), findsOneWidget);
    });

    testWidgets('every category is a tag, grouped as expense and income', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      for (final c in repo.categories) {
        await t.scrollUntilVisible(_chip(c.id), 200, scrollable: find.byType(Scrollable).first);
        expect(_chip(c.id), findsOneWidget, reason: c.name);
      }
      // expense tags come before the income ones
      expect(t.getTopLeft(_chip('e0')).dy, lessThan(t.getTopLeft(_chip('i1')).dy));
    });

    testWidgets('tapping a tag opens the editor with its name filled in', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.scrollUntilVisible(_chip('e1'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(_chip('e1'));
      await t.pumpAndSettle();
      expect(find.text('Edit category'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'Groceries');
    });

    testWidgets('renaming a category updates its tag', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.scrollUntilVisible(_chip('e1'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(_chip('e1'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Supermarket');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.category('e1')!.name, 'Supermarket');
      expect(find.descendant(of: _chip('e1'), matching: find.text('Supermarket')), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    testWidgets('Add (expense) creates a custom expense category', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.scrollUntilVisible(find.byKey(const Key('add-category-expense')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('add-category-expense')));
      await t.pumpAndSettle();
      expect(find.text('New category'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Pets');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final added = repo.categories.singleWhere((c) => c.name == 'Pets');
      expect(added.kind, TxType.expense);
      expect(added.isCustom, isTrue);
      await t.scrollUntilVisible(_chip(added.id), 200, scrollable: find.byType(Scrollable).first);
      expect(_chip(added.id), findsOneWidget);
    });

    testWidgets('Add (income) creates an income category', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.scrollUntilVisible(find.byKey(const Key('add-category-income')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('add-category-income')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Freelance');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.categories.singleWhere((c) => c.name == 'Freelance').kind, TxType.income);
    });

    testWidgets('an empty name is not saved', (t) async {
      final repo = _repo();
      final before = repo.categories.length;
      await _pump(t, const AccountsScreen(), repo);
      await t.scrollUntilVisible(find.byKey(const Key('add-category-expense')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('add-category-expense')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.categories.length, before);
      expect(find.text('New category'), findsOneWidget); // sheet stays open
    });

    testWidgets('an unused category can be deleted; one in use cannot', (t) async {
      final repo = _repo(txs: [sampleTx('1', DateTime(2026, 3, 1), categoryId: 'e0')]);
      await _pump(t, const AccountsScreen(), repo);
      // unused: Fuel (e4)
      await t.scrollUntilVisible(_chip('e4'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(_chip('e4'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.category('e4'), isNull);
      expect(_chip('e4'), findsNothing);
      // in use: Food & Dining (e0)
      await t.scrollUntilVisible(_chip('e0'), -200, scrollable: find.byType(Scrollable).first);
      await t.tap(_chip('e0'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.category('e0'), isNotNull);
      expect(find.text('Category is in use — rename it instead.'), findsOneWidget);
    });

    testWidgets('the account features still work', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      expect(find.text('Total balance'), findsOneWidget);
      await t.tap(find.text('HDFC Savings'));
      await t.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.tap(find.text('New account'));
      await t.pumpAndSettle();
      expect(find.text('New account'), findsWidgets);
    });

    testWidgets('fits a small phone with many categories; scrolls to the end', (t) async {
      final repo = _repo(extra: 25);
      await _pump(t, const AccountsScreen(), repo, size: const Size(360, 640));
      expect(t.takeException(), isNull);
      final last = repo.categories.where((c) => c.id.startsWith('x')).last;
      await t.scrollUntilVisible(_chip(last.id), 200, scrollable: find.byType(Scrollable).first);
      expect(_chip(last.id), findsOneWidget);
      expect(t.getRect(_chip(last.id)).right, lessThanOrEqualTo(360));
      expect(t.takeException(), isNull);
    });
  });

  group('More → Categories still works and shares the same editor', () {
    testWidgets('lists the categories and opens the same editor', (t) async {
      await _pump(t, const CategoriesScreen(), _repo());
      expect(find.text('Expense categories'), findsOneWidget);
      expect(find.text('Income categories'), findsOneWidget);
      await t.tap(find.text('Groceries'));
      await t.pumpAndSettle();
      expect(find.text('Edit category'), findsOneWidget);
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'Groceries');
    });

    testWidgets('a category added on the Accounts tab shows up there too', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.scrollUntilVisible(find.byKey(const Key('add-category-expense')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('add-category-expense')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Gym');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await _pump(t, const CategoriesScreen(), repo);
      expect(find.text('Gym'), findsOneWidget);
    });
  });
}
