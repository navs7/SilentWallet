import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/calc.dart';
import '../core/models.dart';
import '../core/repo.dart';
import '../core/search.dart';
import '../util.dart';

/// Bottom sheet to narrow a search by time period, account, category and
/// amount range. Returns the new filters, or null if dismissed.
Future<SearchFilters?> showSearchFilterSheet(
  BuildContext context,
  SearchFilters current,
) {
  return showModalBottomSheet<SearchFilters>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FilterSheet(initial: current.copy()),
  );
}

class _FilterSheet extends StatefulWidget {
  final SearchFilters initial;
  const _FilterSheet({required this.initial});
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters f = widget.initial;
  final _min = TextEditingController();
  final _max = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (f.minPaise != null) _min.text = formatAmount(f.minPaise! / 100);
    if (f.maxPaise != null) _max.text = formatAmount(f.maxPaise! / 100);
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _setPeriod(String key) {
    final now = DateTime.now();
    setState(() {
      switch (key) {
        case 'month':
          f.from = DateTime(now.year, now.month);
          f.to = DateTime(now.year, now.month + 1);
          f.periodLabel = 'This month';
        case 'last':
          f.from = DateTime(now.year, now.month - 1);
          f.to = DateTime(now.year, now.month);
          f.periodLabel = 'Last month';
        case 'year':
          f.from = DateTime(now.year);
          f.to = DateTime(now.year + 1);
          f.periodLabel = 'This year';
        default:
          f.clearPeriod();
          return;
      }
      f.periodKey = key;
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: f.hasPeriod
          ? DateTimeRange(
              start: f.from!,
              end: f.to!.subtract(const Duration(days: 1)),
            )
          : DateTimeRange(
              start: DateTime(now.year, now.month),
              end: dayOf(now),
            ),
      helpText: 'Select date range',
    );
    if (r == null) return;
    final fmt = DateFormat('d MMM yy');
    setState(() {
      f.from = dayOf(r.start);
      f.to = dayOf(r.end).add(const Duration(days: 1));
      f.periodKey = 'custom';
      f.periodLabel = '${fmt.format(r.start)} – ${fmt.format(r.end)}';
    });
  }

  int? _paise(String t) {
    final v = double.tryParse(t.trim().replaceAll(',', ''));
    return (v == null || v < 0) ? null : (v * 100).round();
  }

  void _apply() {
    var lo = _paise(_min.text);
    var hi = _paise(_max.text);
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    f.minPaise = lo;
    f.maxPaise = hi;
    Navigator.pop(context, f);
  }

  void _reset() {
    setState(() {
      f = SearchFilters();
      _min.clear();
      _max.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final cats = [
      ...repo.categories.where((c) => c.kind == TxType.expense),
      ...repo.categories.where((c) => c.kind == TxType.income),
    ];
    Widget periodChip(String key, String label) => ChoiceChip(
      key: Key('filter-period-$key'),
      label: Text(label),
      selected: f.hasPeriod && f.periodKey == key,
      onSelected: (_) => key == 'custom' ? _pickCustom() : _setPeriod(key),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  key: const Key('filter-reset'),
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Time period', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('filter-period-any'),
                  label: const Text('Any time'),
                  selected: !f.hasPeriod,
                  onSelected: (_) => _setPeriod('any'),
                ),
                periodChip('month', 'This month'),
                periodChip('last', 'Last month'),
                periodChip('year', 'This year'),
                periodChip(
                  'custom',
                  f.periodKey == 'custom' && f.periodLabel != null
                      ? f.periodLabel!
                      : 'Custom range…',
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              key: const Key('filter-account'),
              initialValue: f.accountId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any account'),
                ),
                for (final a in repo.accounts)
                  DropdownMenuItem<String?>(
                    value: a.id,
                    child: Text(a.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => f.accountId = v,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('filter-category'),
              initialValue: f.categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Any category'),
                ),
                for (final c in cats)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(
                      c.kind == TxType.income ? '${c.name} (income)' : c.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => f.categoryId = v,
            ),
            const SizedBox(height: 12),
            Text('Amount', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('filter-min'),
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('to'),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('filter-max'),
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Max',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                key: const Key('filter-apply'),
                onPressed: _apply,
                child: const Text('Apply filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active filters as removable chips, shown under the search box.
class FilterChips extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;
  const FilterChips({
    super.key,
    required this.filters,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final f = filters;
    Widget chip(String key, String label, void Function(SearchFilters) clear) =>
        InputChip(
          key: Key('chip-$key'),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          onDeleted: () => onChanged(f.copy()..also(clear)),
        );

    String amountLabel() {
      final lo = f.minPaise, hi = f.maxPaise;
      if (lo != null && hi != null) {
        return '${money(lo, compact: true)} – ${money(hi, compact: true)}';
      }
      return lo != null
          ? '≥ ${money(lo, compact: true)}'
          : '≤ ${money(hi!, compact: true)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (f.hasPeriod)
            chip('period', f.periodLabel ?? 'Period', (x) => x.clearPeriod()),
          if (f.accountId != null)
            chip(
              'account',
              repo.account(f.accountId)?.name ?? 'Account',
              (x) => x.accountId = null,
            ),
          if (f.categoryId != null)
            chip(
              'category',
              repo.category(f.categoryId)?.name ?? 'Category',
              (x) => x.categoryId = null,
            ),
          if (f.hasAmount)
            chip('amount', amountLabel(), (x) => x.clearAmount()),
          TextButton(
            key: const Key('chip-clear-all'),
            onPressed: () => onChanged(SearchFilters()),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

extension _Also<T> on T {
  /// Runs [f] on this value and returns it (small helper for chip removal).
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
