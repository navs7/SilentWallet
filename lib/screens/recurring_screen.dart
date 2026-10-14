import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../util.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New rule'),
      ),
      body: repo.recurring.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                    'Rent, subscriptions, salary… add a rule and Silent Wallet records it automatically on each due date.',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              for (final r in repo.recurring)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(repo.category(r.categoryId)?.color ?? 0xFF90A4AE),
                    child: Icon(repo.category(r.categoryId)?.iconData ?? Icons.repeat, color: Colors.white),
                  ),
                  title: Text(r.title),
                  subtitle: Text(
                      '${toBeginningOfSentenceCase(r.frequency.name)} • ${r.active ? 'next ${DateFormat('d MMM yyyy').format(r.nextDue)}' : 'paused'}'),
                  trailing: Text(
                      '${r.type == TxType.income ? '+' : '-'}${money(r.amount)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: r.type == TxType.income ? Colors.green.shade600 : Colors.red.shade400)),
                  onTap: () => _edit(context, r),
                ),
            ]),
    );
  }

  Future<void> _edit(BuildContext context, Recurring? r) async {
    final repo = context.read<Repo>();
    if (repo.accounts.where((a) => !a.archived).isEmpty) {
      toast(context, 'Create an account first.');
      return;
    }
    final title = TextEditingController(text: r?.title ?? '');
    final amount = TextEditingController(text: r == null ? '' : (r.amount / 100).toStringAsFixed(2));
    var type = r?.type ?? TxType.expense;
    var freq = r?.frequency ?? Frequency.monthly;
    var accountId = r?.accountId ?? repo.accounts.firstWhere((a) => !a.archived).id;
    String? categoryId = r?.categoryId;
    var start = r?.nextDue ?? dayOf(DateTime.now());
    DateTime? end = r?.endDate;
    var active = r?.active ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final cats = repo.categories.where((c) => c.kind == type).toList();
          if (categoryId != null && !cats.any((c) => c.id == categoryId)) categoryId = null;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(r == null ? 'New recurring rule' : 'Edit rule', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              SegmentedButton<TxType>(
                segments: const [
                  ButtonSegment(value: TxType.expense, label: Text('Expense')),
                  ButtonSegment(value: TxType.income, label: Text('Income')),
                ],
                selected: {type},
                onSelectionChanged: (s) => set(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title (e.g. Rent)')),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Frequency>(
                value: freq,
                decoration: const InputDecoration(labelText: 'Repeats'),
                items: [
                  for (final f in Frequency.values)
                    DropdownMenuItem(value: f, child: Text(toBeginningOfSentenceCase(f.name)!))
                ],
                onChanged: (v) => set(() => freq = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  for (final a in repo.accounts.where((a) => !a.archived || a.id == accountId))
                    DropdownMenuItem(value: a.id, child: Text(a.name))
                ],
                onChanged: (v) => set(() => accountId = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => set(() => categoryId = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text('Next due: ${DateFormat('d MMM yyyy').format(start)}'),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) set(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy),
                title: Text(end == null ? 'No end date' : 'Ends ${DateFormat('d MMM yyyy').format(end!)}'),
                trailing: end == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => set(() => end = null)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: end ?? start,
                      firstDate: start,
                      lastDate: DateTime.now().add(const Duration(days: 3650)));
                  if (d != null) set(() => end = d);
                },
              ),
              if (r != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => set(() => active = v),
                ),
              Row(children: [
                if (r != null)
                  TextButton(
                    onPressed: () async {
                      await repo.deleteRecurring(r.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Delete rule'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final amt = parseAmount(amount.text);
                    if (title.text.trim().isEmpty || amt == null) return;
                    await repo.saveRecurring(Recurring(
                      id: r?.id ?? newId(),
                      title: title.text.trim(),
                      type: type,
                      amount: amt,
                      accountId: accountId,
                      categoryId: categoryId,
                      frequency: freq,
                      nextDue: dayOf(start),
                      anchorDay: start.day,
                      endDate: end,
                      active: active,
                    ));
                    await repo.processRecurring();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }
}
