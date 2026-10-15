import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../theme.dart';
import '../util.dart';

enum _Mode { month, year, custom, all }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Mode _mode = _Mode.month;
  TxType _kind = TxType.expense;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _year = DateTime.now().year;
  DateTimeRange? _custom;

  static final _first = DateTime(2000);

  DateRange _range() {
    switch (_mode) {
      case _Mode.month:
        return monthRange(_month);
      case _Mode.year:
        return DateRange(DateTime(_year), DateTime(_year + 1), '$_year');
      case _Mode.custom:
        final c = _custom!;
        final f = DateFormat('d MMM yyyy');
        return DateRange(
          dayOf(c.start),
          dayOf(c.end).add(const Duration(days: 1)),
          '${f.format(c.start)} – ${f.format(c.end)}',
        );
      case _Mode.all:
        return DateRange(_first, DateTime(DateTime.now().year + 2), 'All time');
    }
  }

  /// Months shown in the trend chart for the current selection.
  List<DateTime> _trendMonths() {
    final now = DateTime.now();
    List<DateTime> span(DateTime from, DateTime to) {
      final out = <DateTime>[];
      for (
        var m = DateTime(from.year, from.month);
        !m.isAfter(DateTime(to.year, to.month));
        m = DateTime(m.year, m.month + 1)
      ) {
        out.add(m);
      }
      return out;
    }

    switch (_mode) {
      case _Mode.month:
        return [
          for (var i = 5; i >= 0; i--) DateTime(_month.year, _month.month - i),
        ];
      case _Mode.year:
        return [for (var m = 1; m <= 12; m++) DateTime(_year, m)];
      case _Mode.custom:
        final all = span(_custom!.start, _custom!.end);
        return all.length > 12 ? all.sublist(all.length - 12) : all;
      case _Mode.all:
        return [
          for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i),
        ];
    }
  }

  Future<void> _setMode(_Mode m) async {
    if (m == _Mode.custom && _custom == null) {
      final r = await _pickRange();
      if (r == null) return;
      setState(() {
        _custom = r;
        _mode = m;
      });
      return;
    }
    setState(() => _mode = m);
  }

  Future<DateTimeRange?> _pickRange() {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: _first,
      lastDate: DateTime(now.year + 5),
      initialDateRange:
          _custom ??
          DateTimeRange(start: DateTime(now.year, now.month), end: dayOf(now)),
      helpText: 'Select date range',
    );
  }

  Future<void> _pickMonth() async {
    var year = _month.year;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Row(
            children: [
              IconButton(
                onPressed: () => set(() => year--),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Text('$year', textAlign: TextAlign.center)),
              IconButton(
                onPressed: () => set(() => year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  if (year == _month.year && m == _month.month)
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, DateTime(year, m)),
                      child: Text(DateFormat('MMM').format(DateTime(2000, m))),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, DateTime(year, m)),
                      child: Text(DateFormat('MMM').format(DateTime(2000, m))),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _month = picked);
  }

  Future<void> _pickYear() async {
    final now = DateTime.now();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select year'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: YearPicker(
            firstDate: _first,
            lastDate: DateTime(now.year + 5),
            selectedDate: DateTime(_year),
            onChanged: (d) => Navigator.pop(ctx, d.year),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked != null) setState(() => _year = picked);
  }

  Widget _selector(BuildContext context, DateRange range) {
    final style = Theme.of(context).textTheme.titleMedium;
    switch (_mode) {
      case _Mode.month:
      case _Mode.year:
        final isMonth = _mode == _Mode.month;
        return Row(
          children: [
            IconButton(
              onPressed: () => setState(() {
                if (isMonth) {
                  _month = DateTime(_month.year, _month.month - 1);
                } else {
                  _year--;
                }
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: isMonth ? _pickMonth : _pickYear,
                icon: const Icon(Icons.event, size: 18),
                label: Text(range.label, style: style),
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                if (isMonth) {
                  _month = DateTime(_month.year, _month.month + 1);
                } else {
                  _year++;
                }
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        );
      case _Mode.custom:
        return Center(
          child: TextButton.icon(
            onPressed: () async {
              final r = await _pickRange();
              if (r != null) setState(() => _custom = r);
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(range.label, style: style),
          ),
        );
      case _Mode.all:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(range.label, style: style),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final range = _range();
    final months = _trendMonths();
    return FutureBuilder<_Data>(
      future: _load(repo, range, months),
      builder: (context, snap) {
        final d = snap.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
          children: [
            SegmentedButton<_Mode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Mode.month, label: Text('Month')),
                ButtonSegment(value: _Mode.year, label: Text('Year')),
                ButtonSegment(value: _Mode.custom, label: Text('Custom')),
                ButtonSegment(value: _Mode.all, label: Text('All')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
            _selector(context, range),
            SegmentedButton<TxType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: TxType.expense, label: Text('Expenses')),
                ButtonSegment(value: TxType.income, label: Text('Income')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            if (d == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _summary(context, d),
              const SizedBox(height: 8),
              _byCategory(context, d, repo),
              if (months.length > 1) ...[
                const SizedBox(height: 8),
                _trend(context, d, months),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<_Data> _load(Repo repo, DateRange r, List<DateTime> months) async {
    final txs = await repo.txBetween(r.from, r.to);
    final d = _Data();
    for (final t in txs) {
      if (t.type == TxType.income) d.income += t.amount;
      if (t.type == TxType.expense) d.expense += t.amount;
      if (t.type == _kind) {
        d.byCat[t.categoryId ?? '_none'] =
            (d.byCat[t.categoryId ?? '_none'] ?? 0) + t.amount;
      }
    }
    if (months.length > 1) {
      final last = months.last;
      for (final t in await repo.txBetween(
        months.first,
        DateTime(last.year, last.month + 1),
      )) {
        // Respect a custom range's exact days inside the first/last month.
        if (_mode == _Mode.custom &&
            (t.date.isBefore(r.from) || !t.date.isBefore(r.to))) {
          continue;
        }
        final k = DateTime(t.date.year, t.date.month);
        d.trend.putIfAbsent(k, () => [0, 0]);
        if (t.type == TxType.expense) d.trend[k]![0] += t.amount;
        if (t.type == TxType.income) d.trend[k]![1] += t.amount;
      }
    }
    return d;
  }

  Widget _summary(BuildContext context, _Data d) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _num('Income', d.income, Colors.green.shade600),
            _num('Expense', d.expense, Colors.red.shade400),
            _num('Saved', d.income - d.expense, cs.primary),
          ],
        ),
      ),
    );
  }

  Widget _num(String l, int v, Color c) => Expanded(
    child: Column(
      children: [
        Text(l, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(
            money(v, compact: true),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
              fontFeatures: kTabularFigures,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _byCategory(BuildContext context, _Data d, Repo repo) {
    final total = d.byCat.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No data for this period')),
        ),
      );
    }
    final entries = d.byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    Color colorOf(String id) => Color(repo.category(id)?.color ?? 0xFF90A4AE);
    String nameOf(String id) => repo.category(id)?.name ?? 'Uncategorized';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              height: 170,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 42,
                  sections: [
                    for (final e in entries)
                      PieChartSectionData(
                        value: e.value.toDouble(),
                        color: colorOf(e.key),
                        radius: 42,
                        title: e.value / total >= 0.07
                            ? '${(e.value * 100 / total).round()}%'
                            : '',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final e in entries)
              ListTile(
                key: Key('cat-row-${e.key}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 7,
                  backgroundColor: colorOf(e.key),
                ),
                title: Text(
                  nameOf(e.key),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: Text(
                  '${money(e.value)}  ·  ${(e.value * 100 / total).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _trend(BuildContext context, _Data d, List<DateTime> months) {
    var maxV = 1;
    for (final m in months) {
      final v = d.trend[m];
      if (v != null) {
        maxV = [maxV, v[0], v[1]].reduce((a, b) => a > b ? a : b);
      }
    }
    final cs = Theme.of(context).colorScheme;
    final dense = months.length > 8;
    final multiYear = months.first.year != months.last.year;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly trend',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: Colors.red.shade400),
                const Text(' Expense   '),
                Icon(Icons.circle, size: 10, color: Colors.green.shade600),
                const Text(' Income'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: maxV / 100 * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: multiYear ? 34 : 22,
                        getTitlesWidget: (v, _) {
                          final m = months[v.toInt()];
                          final label = multiYear && !dense
                              ? DateFormat("MMM\n''yy").format(m)
                              : DateFormat(dense ? 'MMMMM' : 'MMM').format(m);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                        '${DateFormat('MMM yyyy').format(months[g.x])}\n${money((rod.toY * 100).round(), compact: true)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < months.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: dense ? 2 : 4,
                        barRods: [
                          BarChartRodData(
                            toY: (d.trend[months[i]]?[0] ?? 0) / 100,
                            color: Colors.red.shade400,
                            width: dense ? 7 : 10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          BarChartRodData(
                            toY: (d.trend[months[i]]?[1] ?? 0) / 100,
                            color: Colors.green.shade600,
                            width: dense ? 7 : 10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Data {
  int income = 0, expense = 0;
  final Map<String, int> byCat = {};
  final Map<DateTime, List<int>> trend = {}; // month -> [expense, income]
}
