import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../util.dart';

/// The add / edit sheet for a category (shared by the Categories page and the
/// Manage tab).
Future<void> showCategoryEditor(
  BuildContext context,
  Category? c,
  TxType kind,
) async {
  final repo = context.read<Repo>();
  final name = TextEditingController(text: c?.name ?? '');
  var icon = c?.icon ?? 'other';
  var color = c?.color ?? categoryColors.first;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c == null ? 'New category' : 'Edit category',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: c == null,
            ),
            const SizedBox(height: 16),
            const Text('Icon'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in categoryIcons.entries)
                  InkWell(
                    onTap: () => set(() => icon = e.key),
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      backgroundColor: icon == e.key
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        e.value,
                        color: icon == e.key
                            ? Theme.of(ctx).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final col in categoryColors)
                  InkWell(
                    onTap: () => set(() => color = col),
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(col),
                      child: color == col
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (c != null)
                  TextButton(
                    onPressed: () async {
                      final ok = await repo.deleteCategory(c.id);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!ok) {
                        toast(
                          context,
                          'Category is in use — rename it instead.',
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
                    await repo.saveCategory(
                      Category(
                        id: c?.id ?? newId(),
                        name: n,
                        icon: icon,
                        color: color,
                        kind: kind,
                        isCustom: c?.isCustom ?? true,
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

/// Categories as compact tags (tap to edit, "Add" to create), for embedding in
/// another page such as the Manage tab.
class CategoriesSection extends StatelessWidget {
  /// In edit mode the tags show a pencil and open the editor when tapped.
  final bool editing;
  const CategoriesSection({super.key, this.editing = false});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final cs = Theme.of(context).colorScheme;
    Widget group(String title, TxType kind) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in repo.categories.where((c) => c.kind == kind))
                _CategoryTag(
                  category: c,
                  editing: editing,
                  onTap: editing
                      ? () => showCategoryEditor(context, c, kind)
                      : null,
                ),
              ActionChip(
                key: Key('add-category-${kind.name}'),
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                visualDensity: VisualDensity.compact,
                onPressed: () => showCategoryEditor(context, null, kind),
              ),
            ],
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('Expense', TxType.expense),
        group('Income', TxType.income),
      ],
    );
  }
}

class _CategoryTag extends StatelessWidget {
  final Category category;
  final bool editing;
  final VoidCallback? onTap;
  const _CategoryTag({
    required this.category,
    required this.editing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: Key('cat-chip-${category.id}'),
      color: editing ? cs.secondaryContainer : cs.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.iconData,
                size: kCategoryIconSize,
                color: Color(category.color),
              ),
              const SizedBox(width: 5),
              Text(
                category.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (editing) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.edit_outlined,
                  size: 13,
                  color: cs.onSecondaryContainer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
