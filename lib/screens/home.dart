import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/repo.dart';
import '../services/settings.dart';
import 'accounts_screen.dart';
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

  static const _pages = <Widget>[
    TxListScreen(),
    ReportsScreen(),
    AccountsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final backupDue = context.watch<Settings>().backupDue(context.watch<Repo>().hasData);
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tab, children: _pages)),
      floatingActionButton: _tab <= 2
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TxEditScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Transactions'),
          const NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Reports'),
          const NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'Accounts'),
          NavigationDestination(
              icon: Badge(isLabelVisible: backupDue, child: const Icon(Icons.more_horiz)),
              label: 'More'),
        ],
      ),
    );
  }
}
