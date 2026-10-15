import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/repo.dart';
import '../services/lock.dart';
import '../services/settings.dart';
import 'accounts_screen.dart';
import 'back_guard.dart';
import 'more_screen.dart';
import 'reports_screen.dart';
import 'tx_edit.dart';
import 'tx_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _searchOpen = ValueNotifier<bool>(false);
  late final List<Widget> _pages = [
    TxListScreen(searchOpen: _searchOpen),
    const ReportsScreen(),
    const AccountsScreen(),
    const MoreScreen(),
  ];

  @override
  void dispose() {
    _searchOpen.dispose();
    super.dispose();
  }

  /// Back gesture: close the search box, else return to Transactions, else
  /// (handled by BackGuard) press twice to exit.
  bool _onBack() {
    if (context.read<LockController>().locked) {
      SystemNavigator.pop(); // lock screen is showing: just leave the app
      return true;
    }
    if (_searchOpen.value) {
      _searchOpen.value = false;
      return true;
    }
    if (_tab != 0) {
      setState(() => _tab = 0);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final backupDue = context.watch<Settings>().backupDue(
      context.watch<Repo>().hasData,
    );
    return BackGuard(
      onBack: _onBack,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(index: _tab, children: _pages),
        ),
        floatingActionButton: _tab <= 2
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TxEditScreen()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            const NavigationDestination(
              icon: Icon(Icons.pie_chart),
              label: 'Reports',
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: backupDue,
                child: const Icon(Icons.more_horiz),
              ),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
