import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../theme.dart';
import '../util.dart';
import 'categories_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _editAccounts = false;
  bool _editCategories = false;

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
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                'Manage',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Card(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text('Total balance'),
                    const SizedBox(height: 2),
                    Text(
                      money(total),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: kTabularFigures,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            _sectionHeader(
              context,
              title: 'Accounts',
              addKey: const Key('add-account'),
              onAdd: () => showAccountEditor(context, null),
              editKey: const Key('edit-accounts'),
              editing: _editAccounts,
              onToggle: () => setState(() => _editAccounts = !_editAccounts),
            ),
            if (_editAccounts)
              _hint(context, 'Tap an account to change or delete it.'),
            for (final a in repo.accounts)
              ListTile(
                key: Key('account-${a.id}'),
                leading: CircleAvatar(
                  radius: 16,
                  child: Icon(accountTypes[a.type] ?? Icons.folder, size: 18),
                ),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.name + (a.archived ? ' (archived)' : ''),
                      ),
                      if (a.isDefault)
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                subtitle: Text(a.isDefault ? '${a.type} · Default' : a.type),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money(bal[a.id] ?? a.openingBalance),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                    if (_editAccounts) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_outlined, size: 18),
                    ],
                  ],
                ),
                onTap: _editAccounts
                    ? () => showAccountEditor(context, a)
                    : null,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Divider(),
            ),
            _sectionHeader(
              context,
              title: 'Categories',
              editKey: const Key('edit-categories'),
              editing: _editCategories,
              onToggle: () =>
                  setState(() => _editCategories = !_editCategories),
            ),
            if (_editCategories)
              _hint(
                context,
                'Tap a category to rename, recolour or delete it.',
              ),
            CategoriesSection(editing: _editCategories),
          ],
        );
      },
    );
  }
}

Future<void> showAccountEditor(BuildContext context, Account? existing) async {
  final repo = context.read<Repo>();
  final name = TextEditingController(text: existing?.name ?? '');
  final opening = TextEditingController(
    text: existing == null
        ? ''
        : (existing.openingBalance / 100).toStringAsFixed(2),
  );
  var type = existing?.type ?? 'Bank';
  var archived = existing?.archived ?? false;
  var isDefault = existing?.isDefault ?? false;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              existing == null ? 'New account' : 'Edit account',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in accountTypes.keys)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => set(() => type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Opening balance',
                prefixText: '₹ ',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default account'),
              subtitle: const Text('Pre-selected when adding a transaction'),
              value: isDefault && !archived,
              onChanged: archived ? null : (v) => set(() => isDefault = v),
            ),
            if (existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Archived (hide from new entries)'),
                value: archived,
                onChanged: (v) => set(() {
                  archived = v;
                  if (v) isDefault = false;
                }),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      final ok = await repo.deleteAccount(existing.id);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!ok) {
                        toast(
                          context,
                          'Account has transactions — archive it instead.',
                        );
                      }
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final n = name.text.trim();
                    if (n.isEmpty) return;
                    final ob =
                        (double.tryParse(
                              opening.text.replaceAll(',', '').trim(),
                            ) ??
                            0) *
                        100;
                    await repo.saveAccount(
                      Account(
                        id: existing?.id ?? newId(),
                        name: n,
                        type: type,
                        openingBalance: ob.round(),
                        archived: archived,
                        isDefault: isDefault && !archived,
                      ),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A section title with its actions, so it is clear what can be done here.
Widget _sectionHeader(
  BuildContext context, {
  required String title,
  required bool editing,
  required VoidCallback onToggle,
  required Key editKey,
  VoidCallback? onAdd,
  Key? addKey,
}) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
  child: Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (onAdd != null)
        TextButton.icon(
          key: addKey,
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
        ),
      TextButton.icon(
        key: editKey,
        onPressed: onToggle,
        icon: Icon(editing ? Icons.check : Icons.edit_outlined, size: 18),
        label: Text(editing ? 'Done' : 'Edit'),
      ),
    ],
  ),
);

Widget _hint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  ),
);
