import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../util.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    return FutureBuilder<Map<String, int>>(
      future: repo.balances(),
      builder: (context, snap) {
        final bal = snap.data ?? const {};
        final total = repo.accounts
            .where((a) => !a.archived)
            .fold<int>(0, (s, a) => s + (bal[a.id] ?? 0));
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Card(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                const Text('Total balance'),
                const SizedBox(height: 2),
                Text(money(total),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          for (final a in repo.accounts)
            ListTile(
              leading: CircleAvatar(radius: 16, child: Icon(accountTypes[a.type] ?? Icons.folder, size: 18)),
              title: Text(a.name + (a.archived ? ' (archived)' : '')),
              subtitle: Text(a.type),
              trailing: Text(money(bal[a.id] ?? a.openingBalance),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => showAccountEditor(context, a),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: OutlinedButton.icon(
              onPressed: () => showAccountEditor(context, null),
              icon: const Icon(Icons.add),
              label: const Text('New account'),
            ),
          ),
        ]);
      },
    );
  }
}

Future<void> showAccountEditor(BuildContext context, Account? existing) async {
  final repo = context.read<Repo>();
  final name = TextEditingController(text: existing?.name ?? '');
  final opening = TextEditingController(
      text: existing == null ? '' : (existing.openingBalance / 100).toStringAsFixed(2));
  var type = existing?.type ?? 'Bank';
  var archived = existing?.archived ?? false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(existing == null ? 'New account' : 'Edit account',
              style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in accountTypes.keys) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => set(() => type = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Opening balance', prefixText: '₹ '),
          ),
          if (existing != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Archived (hide from new entries)'),
              value: archived,
              onChanged: (v) => set(() => archived = v),
            ),
          const SizedBox(height: 12),
          Row(children: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  final ok = await repo.deleteAccount(existing.id);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  if (!ok) toast(context, 'Account has transactions — archive it instead.');
                },
                child: const Text('Delete'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: () async {
                final n = name.text.trim();
                if (n.isEmpty) return;
                final ob = (double.tryParse(opening.text.replaceAll(',', '').trim()) ?? 0) * 100;
                await repo.saveAccount(Account(
                  id: existing?.id ?? newId(),
                  name: n,
                  type: type,
                  openingBalance: ob.round(),
                  archived: archived,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ]),
        ]),
      ),
    ),
  );
}
