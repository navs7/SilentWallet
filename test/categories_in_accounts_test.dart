import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/screens/accounts_screen.dart';
import 'package:silentwallet/screens/more_screen.dart';
import 'package:silentwallet/services/lock.dart';
import 'package:silentwallet/services/settings.dart';
import 'package:silentwallet/theme.dart';

import 'test_support.dart';

FakeRepo _repo({int extra = 0, List<Tx> txs = const []}) {
  final r = FakeRepo(txs: txs);
  r.accounts = sampleAccounts();
  r.categories = sampleCategories(extraCustom: extra);
  return r;
}

Future<void> _pump(
  WidgetTester t,
  Widget page,
  FakeRepo repo, {
  Size size = const Size(393, 851),
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await Settings.load();
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Repo>.value(value: repo),
        ChangeNotifierProvider<Settings>.value(value: settings),
        ChangeNotifierProvider<LockController>.value(
          value: LockController(settings),
        ),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: compactText,
        home: Scaffold(body: page),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Finder _chip(String id) => find.byKey(Key('cat-chip-$id'));
Finder _account(String id) => find.byKey(Key('account-$id'));
final _editAccounts = find.byKey(const Key('edit-accounts'));
final _editCategories = find.byKey(const Key('edit-categories'));
final _addAccount = find.byKey(const Key('add-account'));
Finder _scrollable() => find.byType(Scrollable).first;
Future<void> _show(WidgetTester t, Finder f) =>
    t.scrollUntilVisible(f, 200, scrollable: _scrollable());

/// The pencil shown on an item while its section is in edit mode.
Finder _pencil(Finder item) =>
    find.descendant(of: item, matching: find.byIcon(Icons.edit_outlined));

void main() {
  group('Manage page: layout and the visible actions', () {
    testWidgets(
      'has a Manage title, an Accounts section and a Categories section',
      (t) async {
        await _pump(t, const AccountsScreen(), _repo());
        expect(find.text('Manage'), findsOneWidget);
        expect(find.text('Total balance'), findsOneWidget);
        expect(find.text('Accounts'), findsOneWidget);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('HDFC Savings'), findsOneWidget);
      },
    );

    testWidgets('each section says what you can do: Add / Edit buttons', (
      t,
    ) async {
      await _pump(t, const AccountsScreen(), _repo());
      // accounts: Add + Edit
      expect(
        find.descendant(of: _addAccount, matching: find.text('Add')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _editAccounts, matching: find.text('Edit')),
        findsOneWidget,
      );
      // categories: Edit, and an Add tag for each kind
      expect(
        find.descendant(of: _editCategories, matching: find.text('Edit')),
        findsOneWidget,
      );
      await _show(t, find.byKey(const Key('add-category-income')));
      expect(find.byKey(const Key('add-category-expense')), findsOneWidget);
      expect(find.byKey(const Key('add-category-income')), findsOneWidget);
    });

    testWidgets('the old "New account" button at the bottom is gone', (
      t,
    ) async {
      await _pump(t, const AccountsScreen(), _repo());
      expect(find.text('New account'), findsNothing);
    });

    testWidgets('every category is a tag, expense ones before income', (
      t,
    ) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      for (final c in repo.categories) {
        await _show(t, _chip(c.id));
        expect(_chip(c.id), findsOneWidget, reason: c.name);
      }
      expect(
        t.getTopLeft(_chip('e0')).dy,
        lessThan(t.getTopLeft(_chip('i1')).dy),
      );
    });
  });

  group('Edit mode for accounts', () {
    testWidgets('outside edit mode, tapping an account does nothing', (
      t,
    ) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.tap(_account('a2'));
      await t.pumpAndSettle();
      expect(find.text('Edit account'), findsNothing);
      expect(_pencil(_account('a2')), findsNothing);
    });

    testWidgets('Edit shows a pencil on every account and turns into Done', (
      t,
    ) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.tap(_editAccounts);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: _editAccounts, matching: find.text('Done')),
        findsOneWidget,
      );
      expect(_pencil(_account('a1')), findsOneWidget);
      expect(_pencil(_account('a2')), findsOneWidget);
      expect(
        find.text('Tap an account to change or delete it.'),
        findsOneWidget,
      );
      await t.tap(_editAccounts); // Done
      await t.pumpAndSettle();
      expect(_pencil(_account('a1')), findsNothing);
      expect(
        find.descendant(of: _editAccounts, matching: find.text('Edit')),
        findsOneWidget,
      );
    });

    testWidgets('in edit mode a tap opens the account editor', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.tap(_editAccounts);
      await t.pumpAndSettle();
      await t.tap(_account('a2'));
      await t.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).first).controller!.text,
        'HDFC Savings',
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Edit account'), findsNothing);
    });

    testWidgets('Add opens the new-account sheet and the account is created', (
      t,
    ) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.tap(_addAccount);
      await t.pumpAndSettle();
      expect(find.text('New account'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Axis Credit Card');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.accounts.any((a) => a.name == 'Axis Credit Card'), isTrue);
      expect(find.text('Axis Credit Card'), findsOneWidget);
    });

    testWidgets('Add works without entering edit mode', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      expect(
        find.descendant(of: _editAccounts, matching: find.text('Edit')),
        findsOneWidget,
      );
      await t.tap(_addAccount);
      await t.pumpAndSettle();
      expect(find.text('New account'), findsOneWidget);
    });
  });

  group('Edit mode for categories', () {
    testWidgets('outside edit mode, tapping a tag does nothing', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      await _show(t, _chip('e1'));
      await t.tap(_chip('e1'));
      await t.pumpAndSettle();
      expect(find.text('Edit category'), findsNothing);
      expect(_pencil(_chip('e1')), findsNothing);
    });

    testWidgets('Edit shows a pencil on the tags and a hint', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.tap(_editCategories);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: _editCategories, matching: find.text('Done')),
        findsOneWidget,
      );
      expect(
        find.text('Tap a category to rename, recolour or delete it.'),
        findsOneWidget,
      );
      await _show(t, _chip('e1'));
      expect(_pencil(_chip('e1')), findsOneWidget);
      expect(_pencil(_chip('i1')), findsOneWidget);
    });

    testWidgets('the two edit modes are independent', (t) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.tap(_editAccounts);
      await t.pumpAndSettle();
      await _show(t, _chip('e1'));
      expect(_pencil(_chip('e1')), findsNothing); // categories still read-only
      expect(
        find.descendant(of: _editCategories, matching: find.text('Edit')),
        findsOneWidget,
      );
      await t.tap(_editCategories);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: _editAccounts, matching: find.text('Done')),
        findsOneWidget,
      ); // still on
      await _show(t, _chip('e1'));
      expect(_pencil(_chip('e1')), findsOneWidget);
    });

    testWidgets('in edit mode a tap opens the editor with the name filled in', (
      t,
    ) async {
      await _pump(t, const AccountsScreen(), _repo());
      await t.tap(_editCategories);
      await t.pumpAndSettle();
      await _show(t, _chip('e1'));
      await t.tap(_chip('e1'));
      await t.pumpAndSettle();
      expect(find.text('Edit category'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Groceries',
      );
    });

    testWidgets('renaming a category updates its tag', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await t.tap(_editCategories);
      await t.pumpAndSettle();
      await _show(t, _chip('e1'));
      await t.tap(_chip('e1'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Supermarket');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.category('e1')!.name, 'Supermarket');
      expect(
        find.descendant(of: _chip('e1'), matching: find.text('Supermarket')),
        findsOneWidget,
      );
    });

    testWidgets('the Add tags create categories without edit mode', (t) async {
      final repo = _repo();
      await _pump(t, const AccountsScreen(), repo);
      await _show(t, find.byKey(const Key('add-category-expense')));
      await t.tap(find.byKey(const Key('add-category-expense')));
      await t.pumpAndSettle();
      expect(find.text('New category'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Pets');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final added = repo.categories.singleWhere((c) => c.name == 'Pets');
      expect(added.kind, TxType.expense);
      expect(added.isCustom, isTrue);
      await _show(t, find.byKey(const Key('add-category-income')));
      await t.tap(find.byKey(const Key('add-category-income')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Freelance');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        repo.categories.singleWhere((c) => c.name == 'Freelance').kind,
        TxType.income,
      );
    });

    testWidgets('an empty name is not saved', (t) async {
      final repo = _repo();
      final before = repo.categories.length;
      await _pump(t, const AccountsScreen(), repo);
      await _show(t, find.byKey(const Key('add-category-expense')));
      await t.tap(find.byKey(const Key('add-category-expense')));
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(repo.categories.length, before);
      expect(find.text('New category'), findsOneWidget);
    });

    testWidgets('an unused category can be deleted; one in use cannot', (
      t,
    ) async {
      final repo = _repo(
        txs: [sampleTx('1', DateTime(2026, 3, 1), categoryId: 'e0')],
      );
      await _pump(t, const AccountsScreen(), repo);
      await t.tap(_editCategories);
      await t.pumpAndSettle();
      await _show(t, _chip('e4'));
      await t.tap(_chip('e4')); // Fuel: unused
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.category('e4'), isNull);
      expect(_chip('e4'), findsNothing);
      await t.scrollUntilVisible(_chip('e0'), -200, scrollable: _scrollable());
      await t.tap(_chip('e0')); // Food & Dining: in use
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(repo.category('e0'), isNotNull);
      expect(
        find.text('Category is in use — rename it instead.'),
        findsOneWidget,
      );
    });
  });

  group('small phones and the More page', () {
    testWidgets(
      'both edit modes with many categories: no overflow, scrolls to the end',
      (t) async {
        final repo = _repo(extra: 25);
        await _pump(
          t,
          const AccountsScreen(),
          repo,
          size: const Size(360, 640),
        );
        await t.tap(_editAccounts);
        await t.pumpAndSettle();
        await t.tap(_editCategories);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final last = repo.categories.where((c) => c.id.startsWith('x')).last;
        await _show(t, _chip(last.id));
        expect(t.getRect(_chip(last.id)).right, lessThanOrEqualTo(360));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('the More page no longer has a Categories row', (t) async {
      await _pump(t, const MoreScreen(), _repo());
      expect(find.text('Categories'), findsNothing);
      expect(find.byIcon(Icons.category), findsNothing);
      // its other rows are still there
      expect(find.text('Recurring expenses'), findsOneWidget);
      expect(find.text('Backup & restore'), findsOneWidget);
    });
  });
}
