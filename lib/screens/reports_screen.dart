import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../util.dart';

enum _Period { month, lastMonth, year, all }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _period = _Period.month;
  TxType _kind = TxType.expense;

  DateRange _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.month:
        return monthRange(now);
      case _Period.lastMonth:
        return monthRange(DateTime(now.year, now.month - 1));
      case _Period.year:
        return DateRange(DateTime(now.year), DateTime(now.year + 1), '${now.year}');
      case _Period.all:
        return DateRange(DateTime(2000), DateTime(now.year + 2), 'All time');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final range = _range();
    return FutureBuilder<_Data>(
      future: _load(repo, range),
      builder: (context, snap) {
        final d = snap.data;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          SegmentedButton<_Period>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Period.month, label: Text('This month')),
              ButtonSegment(value: _Period.lastMonth, label: Text('Last')),
              ButtonSegment(value: _Period.year, label: Text('Year')),
              ButtonSegment(value: _Period.all, label: Text('All')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TxType>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('Expenses')),
              ButtonSegment(value: TxType.income, label: Text('Income')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (d == null)
            const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
          else ...[
            _summary(context, d),
            const SizedBox(height: 16),
            _byCategory(context, d, repo),
            const SizedBox(height: 16),
            _trend(context, d),
          ],
        ]);
      },
    );
  }

  Future<_Data> _load(Repo repo, DateRange r) async {
    final txs = await repo.txBetween(r.from, r.to);
    final d = _Data();
    for (final t in txs) {
      if (t.type == TxType.income) d.income += t.amount;
      if (t.type == TxType.expense) d.expense += t.amount;
      if (t.type == _kind) {
        d.byCat[t.categoryId ?? '_none'] = (d.byCat[t.categoryId ?? '_none'] ?? 0) + t.amount;
      }
    }
    // 6-month trend ending now (independent of the period filter)
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5);
    for (final t in await repo.txBetween(start, DateTime(now.year, now.month + 1))) {
      final k = DateTime(t.date.year, t.date.month);
      d.trend.putIfAbsent(k, () => [0, 0]);
      if (t.type == TxType.expense) d.trend[k]![0] += t.amount;
      if (t.type == TxType.income) d.trend[k]![1] += t.amount;
    }
    return d;
  }

  Widget _summary(BuildContext context, _Data d) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          _num('Income', d.income, Colors.green.shade600),
          _num('Expense', d.expense, Colors.red.shade400),
          _num('Saved', d.income - d.expense, cs.primary),
        ]),
      ),
    );
  }

  Widget _num(String l, int v, Color c) => Expanded(
        child: Column(children: [
          Text(l, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          FittedBox(
              child: Text(money(v, compact: true),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _byCategory(BuildContext context, _Data d, Repo repo) {
    final total = d.byCat.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return const Card(
          child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No data for this period'))));
    }
    final entries = d.byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    Color colorOf(String id) => Color(repo.category(id)?.color ?? 0xFF90A4AE);
    String nameOf(String id) => repo.category(id)?.name ?? 'Uncategorized';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            height: 200,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: [
                for (final e in entries)
                  PieChartSectionData(
                    value: e.value.toDouble(),
                    color: colorOf(e.key),
                    radius: 48,
                    title: e.value / total >= 0.07 ? '${(e.value * 100 / total).round()}%' : '',
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
              ],
            )),
          ),
          const SizedBox(height: 12),
          for (final e in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 6, backgroundColor: colorOf(e.key)),
              title: Text(nameOf(e.key)),
              trailing: Text('${money(e.value)}  ·  ${(e.value * 100 / total).toStringAsFixed(0)}%'),
            ),
        ]),
      ),
    );
  }

  Widget _trend(BuildContext context, _Data d) {
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    var maxV = 1;
    for (final m in months) {
      final v = d.trend[m];
      if (v != null) {
        maxV = [maxV, v[0], v[1]].reduce((a, b) => a > b ? a : b);
      }
    }
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Last 6 months', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.circle, size: 10, color: Colors.red.shade400),
            const Text(' Expense   '),
            Icon(Icons.circle, size: 10, color: Colors.green.shade600),
            const Text(' Income'),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(BarChartData(
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
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(DateFormat('MMM').format(months[v.toInt()]),
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                      money((rod.toY * 100).round(), compact: true),
                      const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
              barGroups: [
                for (var i = 0; i < months.length; i++)
                  BarChartGroupData(x: i, barsSpace: 4, barRods: [
                    BarChartRodData(
                        toY: (d.trend[months[i]]?[0] ?? 0) / 100,
                        color: Colors.red.shade400,
                        width: 10,
                        borderRadius: BorderRadius.circular(3)),
                    BarChartRodData(
                        toY: (d.trend[months[i]]?[1] ?? 0) / 100,
                        color: Colors.green.shade600,
                        width: 10,
                        borderRadius: BorderRadius.circular(3)),
                  ]),
              ],
            )),
          ),
        ]),
      ),
    );
  }
}

class _Data {
  int income = 0, expense = 0;
  final Map<String, int> byCat = {};
  final Map<DateTime, List<int>> trend = {}; // month -> [expense, income]
}
