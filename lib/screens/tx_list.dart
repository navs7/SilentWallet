import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../core/search.dart';
import '../util.dart';
import 'search_filter_sheet.dart';
import 'tx_edit.dart';

class TxListScreen extends StatefulWidget {
  /// Shared with the home screen so the back gesture can close the search box.
  final ValueNotifier<bool> searchOpen;
  const TxListScreen({super.key, required this.searchOpen});
  @override
  State<TxListScreen> createState() => _TxListScreenState();
}

class _TxListScreenState extends State<TxListScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _search = '';
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  SearchFilters _filters = SearchFilters();

  bool get _searching => widget.searchOpen.value;

  @override
  void initState() {
    super.initState();
    widget.searchOpen.addListener(_onSearchFlag);
  }

  @override
  void dispose() {
    widget.searchOpen.removeListener(_onSearchFlag);
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSearchFlag() {
    if (!mounted) return;
    setState(() {
      if (!widget.searchOpen.value) {
        _search = '';
        _filters = SearchFilters();
        _ctl.clear();
        _focus.unfocus();
      }
    });
  }

  void _shift(int d) =>
      setState(() => _month = DateTime(_month.year, _month.month + d));

  Future<void> _openFilters() async {
    _focus.unfocus();
    final r = await showSearchFilterSheet(context, _filters);
    if (r != null && mounted) setState(() => _filters = r);
  }

  void _useQuery(String q) {
    _ctl.text = q;
    _ctl.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _search = q);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final range = monthRange(_month);
    final hasQuery =
        _searching && (_search.trim().isNotEmpty || _filters.isActive);
    final Future<List<Tx>> future = hasQuery
        ? repo.search(_search, filters: _filters) // every date unless filtered
        : _searching
        ? Future.value(const <Tx>[])
        : repo.txBetween(range.from, range.to);

    return FutureBuilder<List<Tx>>(
      future: future,
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

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _searching
                    ? Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctl,
                              focusNode: _focus,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: 'Search notes, categories, accounts, amounts',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Filters',
                            onPressed: _openFilters,
                            icon: Badge(
                              isLabelVisible: _filters.isActive,
                              child: const Icon(Icons.tune),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close search',
                            onPressed: () => widget.searchOpen.value = false,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          IconButton(
                            onPressed: () => _shift(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              range.label,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _shift(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                          IconButton(
                            tooltip: 'Search',
                            onPressed: () => widget.searchOpen.value = true,
                            icon: const Icon(Icons.search),
                          ),
                        ],
                      ),
              ),
            ),
            if (_searching && _filters.isActive)
              SliverToBoxAdapter(
                child: FilterChips(
                  filters: _filters,
                  onChanged: (f) => setState(() => _filters = f),
                ),
              ),
            if (_searching && !hasQuery)
              SliverToBoxAdapter(child: _RecentNotes(onPick: _useQuery)),
            if (!_searching || hasQuery) ...[
              SliverToBoxAdapter(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _Stat('Income', income, Colors.green.shade600),
                        _Stat('Expense', expense, Colors.red.shade400),
                        _Stat(
                          'Net',
                          income - expense,
                          Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasQuery && snap.hasData)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                    child: Text(
                      '${txs.length}${txs.length >= 500 ? '+' : ''} result${txs.length == 1 ? '' : 's'}${_filters.hasPeriod ? '' : ' across all dates'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
            if (snap.hasData && txs.isEmpty && (!_searching || hasQuery))
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    hasQuery
                        ? (_search.trim().isEmpty
                              ? 'No transactions match these filters.'
                              : 'No transactions match "${_search.trim()}".')
                        : 'No transactions this month.\nTap Add to record one.',
                    textAlign: TextAlign.center,
                  ),
                ),
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dayLabel(d),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            money(net),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                    for (final t in list) TxTile(tx: t),
                  ],
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 76)),
          ],
        );
      },
    );
  }
}

/// Shown under an empty search box: notes used before, one tap to search them.
class _RecentNotes extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _RecentNotes({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return FutureBuilder<List<NoteEntry>>(
      future: repo.noteHistory(),
      builder: (context, snap) {
        final notes = rankNotes(snap.data ?? const [], '', limit: 14);
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notes.isEmpty
                    ? 'Type to search across all your notes, categories, accounts and amounts.'
                    : 'Recent notes',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in notes)
                    ActionChip(
                      avatar: const Icon(Icons.history, size: 16),
                      label: Text(n.note),
                      onPressed: () => onPick(n.note),
                    ),
                ],
              ),
            ],
          ),
        );
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
    child: Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            money(paise, compact: true),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
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
    final title = isTransfer ? 'Transfer' : (cat?.name ?? 'Uncategorized');
    final subtitle = [
      isTransfer ? '$acc → ${repo.account(tx.toAccountId)?.name ?? '?'}' : acc,
      if (tx.note.isNotEmpty) tx.note,
    ].join(' • ');
    return ListTile(
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: isTransfer
            ? Theme.of(context).colorScheme.primaryContainer
            : Color(cat?.color ?? 0xFF90A4AE),
        child: Icon(
          isTransfer ? Icons.swap_horiz : (cat?.iconData ?? Icons.category),
          size: 21,
          color: isTransfer
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Colors.white,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tx.receipt != null)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.receipt, size: 18),
            ),
          if (tx.recurringId != null)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.repeat, size: 18),
            ),
          Text(
            '$sign${money(tx.amount)}',
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TxEditScreen(existing: tx)),
      ),
    );
  }
}
