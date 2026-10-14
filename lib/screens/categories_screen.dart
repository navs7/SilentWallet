import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../util.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    Widget section(String title, TxType kind) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final c in repo.categories.where((c) => c.kind == kind))
              ListTile(
                leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c.color),
                    child: Icon(c.iconData, size: 18, color: Colors.white)),
                title: Text(c.name),
                trailing: c.isCustom ? const Icon(Icons.edit, size: 18) : null,
                onTap: () => _edit(context, c, kind),
              ),
            TextButton.icon(
              onPressed: () => _edit(context, null, kind),
              icon: const Icon(Icons.add),
              label: Text('Add ${kind.name} category'),
            ),
          ],
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(children: [
        section('Expense categories', TxType.expense),
        section('Income categories', TxType.income),
        const SizedBox(height: 32),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, Category? c, TxType kind) async {
    final repo = context.read<Repo>();
    final name = TextEditingController(text: c?.name ?? '');
    var icon = c?.icon ?? 'other';
    var color = c?.color ?? categoryColors.first;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c == null ? 'New category' : 'Edit category',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), autofocus: c == null),
            const SizedBox(height: 16),
            const Text('Icon'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in categoryIcons.entries)
                InkWell(
                  onTap: () => set(() => icon = e.key),
                  borderRadius: BorderRadius.circular(24),
                  child: CircleAvatar(
                    backgroundColor: icon == e.key ? Theme.of(ctx).colorScheme.primary : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    child: Icon(e.value, color: icon == e.key ? Theme.of(ctx).colorScheme.onPrimary : null),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('Colour'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final col in categoryColors)
                InkWell(
                  onTap: () => set(() => color = col),
                  borderRadius: BorderRadius.circular(24),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(col),
                    child: color == col ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              if (c != null)
                TextButton(
                  onPressed: () async {
                    final ok = await repo.deleteCategory(c.id);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!ok) toast(context, 'Category is in use — rename it instead.');
                  },
                  child: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final n = name.text.trim();
                  if (n.isEmpty) return;
                  await repo.saveCategory(Category(
                    id: c?.id ?? newId(),
                    name: n,
                    icon: icon,
                    color: color,
                    kind: kind,
                    isCustom: c?.isCustom ?? true,
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
}
