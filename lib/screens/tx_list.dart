import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../services/settings.dart';
import '../util.dart';
import 'backup_screen.dart';
import 'tx_edit.dart';

class TxListScreen extends StatefulWidget {
  const TxListScreen({super.key});
  @override
  State<TxListScreen> createState() => _TxListScreenState();
}

class _TxListScreenState extends State<TxListScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _search = '';
  bool _searching = false;

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final settings = context.watch<Settings>();
    final range = monthRange(_month);

    return FutureBuilder<List<Tx>>(
      future: repo.txBetween(range.from, range.to, search: _search),
      builder: (context, snap) {
        final txs = snap.data ?? const <Tx>[];
        var income = 0, expense = 0;
        for (final t in txs) {
          if (t.type == TxType.income) income += t.amount;
          if (t.type == TxType.expense) expense += t.amount;
        }
        final groups = <DateTime, List<Tx>>{};
        for (final t in txs) {
          groups.putIfAbsent(dayOf(t.date), () => []).add(t);
        }
        final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: _searching
                  ? Row(children: [
                      Expanded(
                        child: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                              hintText: 'Search notes', prefixIcon: Icon(Icons.search)),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      IconButton(
                          onPressed: () => setState(() {
                                _searching = false;
                                _search = '';
                              }),
                          icon: const Icon(Icons.close)),
                    ])
                  : Row(children: [
                      IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                      Expanded(
                        child: Text(range.label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
                      IconButton(
                          onPressed: () => setState(() => _searching = true),
                          icon: const Icon(Icons.search)),
                    ]),
            ),
          ),
          if (settings.backupDue(repo.hasData))
            SliverToBoxAdapter(child: _BackupBanner(settings: settings)),
          SliverToBoxAdapter(
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  _Stat('Income', income, Colors.green.shade600),
                  _Stat('Expense', expense, Colors.red.shade400),
                  _Stat('Net', income - expense,
                      Theme.of(context).colorScheme.primary),
                ]),
              ),
            ),
          ),
          if (snap.hasData && txs.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No transactions this month.\nTap Add to record one.',
                  textAlign: TextAlign.center)),
            ),
          SliverList.builder(
            itemCount: days.length,
            itemBuilder: (context, i) {
              final d = days[i];
              final list = groups[d]!;
              var net = 0;
              for (final t in list) {
                if (t.type == TxType.income) net += t.amount;
                if (t.type == TxType.expense) net -= t.amount;
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(dayLabel(d),
                            style: Theme.of(context).textTheme.labelLarge)),
                    Text(money(net),
                        style: Theme.of(context).textTheme.labelLarge),
                  ]),
                ),
                for (final t in list) TxTile(tx: t),
              ]);
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ]);
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int paise;
  final Color color;
  const _Stat(this.label, this.paise, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(money(paise, compact: true),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

class _BackupBanner extends StatelessWidget {
  final Settings settings;
  const _BackupBanner({required this.settings});
  @override
  Widget build(BuildContext context) {
    final last = settings.lastBackup;
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded),
        title: Text(last == null ? 'No backup yet' : 'Last backup ${DateFormat('d MMM').format(last)}'),
        subtitle: const Text('Your data exists only on this phone. Export an encrypted backup.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BackupScreen())),
      ),
    );
  }
}

class TxTile extends StatelessWidget {
  final Tx tx;
  const TxTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final cat = repo.category(tx.categoryId);
    final acc = repo.account(tx.accountId)?.name ?? '?';
    final isTransfer = tx.type == TxType.transfer;
    final color = switch (tx.type) {
      TxType.income => Colors.green.shade600,
      TxType.expense => Colors.red.shade400,
      TxType.transfer => Theme.of(context).colorScheme.primary,
    };
    final sign = switch (tx.type) {
      TxType.income => '+',
      TxType.expense => '-',
      TxType.transfer => '',
    };
    final title = isTransfer
        ? 'Transfer'
        : (cat?.name ?? 'Uncategorized');
    final subtitle = [
      isTransfer ? '$acc → ${repo.account(tx.toAccountId)?.name ?? '?'}' : acc,
      if (tx.note.isNotEmpty) tx.note,
    ].join(' • ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isTransfer ? Theme.of(context).colorScheme.primaryContainer : Color(cat?.color ?? 0xFF90A4AE),
        child: Icon(isTransfer ? Icons.swap_horiz : (cat?.iconData ?? Icons.category),
            color: isTransfer ? Theme.of(context).colorScheme.onPrimaryContainer : Colors.white),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (tx.receipt != null)
          const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.receipt, size: 16)),
        if (tx.recurringId != null)
          const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.repeat, size: 16)),
        Text('$sign${money(tx.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => TxEditScreen(existing: tx))),
    );
  }
}
