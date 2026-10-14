import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../services/lock.dart';
import '../util.dart';

/// Add / edit transaction. The page is a fixed, non-scrolling layout: the
/// amount is typed on the built-in number pad (so no system keyboard pushes
/// things around), the note opens in a small dialog, and the category tags
/// resize themselves to fit whatever height is left.
class TxEditScreen extends StatefulWidget {
  final Tx? existing;
  const TxEditScreen({super.key, this.existing});
  @override
  State<TxEditScreen> createState() => _TxEditScreenState();
}

class _TxEditScreenState extends State<TxEditScreen> {
  late TxType _type;
  String _amount = '';
  String _note = '';
  String? _categoryId;
  String? _accountId;
  String? _toAccountId;
  late DateTime _date;

  String? _receiptName; // already stored (encrypted) file
  Uint8List? _newReceipt; // picked, not yet stored
  bool _receiptRemoved = false;
  Uint8List? _receiptPreview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    final repo = context.read<Repo>();
    _type = t?.type ?? TxType.expense;
    if (t != null) {
      var s = (t.amount / 100).toStringAsFixed(2);
      if (s.endsWith('.00')) {
        s = s.substring(0, s.length - 3);
      } else if (s.endsWith('0')) {
        s = s.substring(0, s.length - 1);
      }
      _amount = s;
    }
    _note = t?.note ?? '';
    _categoryId = t?.categoryId;
    final active = repo.accounts.where((a) => !a.archived).toList();
    _accountId = t?.accountId ?? (active.isNotEmpty ? active.first.id : null);
    _toAccountId = t?.toAccountId;
    _date = t?.date ?? DateTime.now();
    _receiptName = t?.receipt;
    if (_receiptName != null) {
      repo.readReceipt(_receiptName!).then((b) {
        if (mounted) setState(() => _receiptPreview = b);
      });
    }
  }

  // ---------- amount pad ----------
  void _key(String k) {
    setState(() {
      if (k == '<') {
        if (_amount.isNotEmpty) {
          _amount = _amount.substring(0, _amount.length - 1);
        }
        return;
      }
      if (k == '.') {
        if (_amount.contains('.')) return;
        if (_amount.isEmpty) _amount = '0';
        _amount += '.';
        return;
      }
      final dot = _amount.indexOf('.');
      if (dot >= 0 && _amount.length - dot > 2) return; // max 2 decimals
      if (dot < 0 && _amount.length >= 9) return;
      _amount = _amount == '0' ? k : _amount + k;
    });
  }

  String get _amountText {
    if (_amount.isEmpty) return '0';
    final parts = _amount.split('.');
    final whole = NumberFormat.decimalPattern('en_IN')
        .format(parts[0].isEmpty ? 0 : int.parse(parts[0]));
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  int? get _amountPaise => parseAmount(
    _amount.endsWith('.') ? _amount.substring(0, _amount.length - 1) : _amount,
  );

  // ---------- note / date / receipt ----------
  Future<void> _editNote() async {
    final c = TextEditingController(text: _note);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What was this for?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (v != null) setState(() => _note = v);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(
        () =>
            _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute),
      );
    }
  }

  Future<void> _pickReceipt(ImageSource src) async {
    final lock = context.read<LockController>();
    final x = await lock.suspendLock(
      () => ImagePicker().pickImage(
        source: src,
        maxWidth: 1600,
        imageQuality: 75,
      ),
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    try {
      await File(x.path).delete(); // don't leave a plain copy in the cache
    } catch (_) {}
    setState(() {
      _newReceipt = bytes;
      _receiptPreview = bytes;
      _receiptRemoved = false;
    });
  }

  bool get _hasReceipt => _receiptPreview != null && !_receiptRemoved;

  void _receiptSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasReceipt)
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View receipt'),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(
                        child: Image.memory(_receiptPreview!),
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickReceipt(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickReceipt(ImageSource.gallery);
              },
            ),
            if (_hasReceipt)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove receipt'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _receiptRemoved = true;
                    _newReceipt = null;
                    _receiptPreview = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------- save / delete ----------
  Future<void> _save() async {
    final amt = _amountPaise;
    if (amt == null) return toast(context, 'Enter an amount.');
    if (_accountId == null) {
      return toast(context, 'Create an account first (Accounts tab).');
    }
    if (_type == TxType.transfer && _toAccountId == null) {
      return toast(context, 'Choose the destination account.');
    }
    setState(() => _saving = true);
    final repo = context.read<Repo>();
    final old = widget.existing;
    String? receipt = _receiptName;
    if (_newReceipt != null) {
      receipt = await repo.saveReceipt(_newReceipt!);
      if (old?.receipt != null) await repo.deleteReceipt(old!.receipt!);
    } else if (_receiptRemoved) {
      if (old?.receipt != null) await repo.deleteReceipt(old!.receipt!);
      receipt = null;
    }
    await repo.saveTx(
      Tx(
        id: old?.id ?? newId(),
        type: _type,
        amount: amt,
        accountId: _accountId!,
        toAccountId: _type == TxType.transfer ? _toAccountId : null,
        categoryId: _type == TxType.transfer ? null : _categoryId,
        note: _note,
        date: _date,
        receipt: receipt,
        recurringId: old?.recurringId,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      'Delete transaction?',
      'This cannot be undone.',
    );
    if (!ok) return;
    if (!mounted) return;
    await context.read<Repo>().deleteTx(widget.existing!);
    if (mounted) Navigator.pop(context);
  }

  // ---------- UI ----------
  Widget _accountDropdown(
    List<Account> accounts,
    String label,
    String? value,
    ValueChanged<String?> onChanged, {
    Key? key,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Text(a.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _pill(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 38),
          backgroundColor: active ? cs.primaryContainer : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _padKey(String k, {IconData? icon}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _key(k),
            onLongPress: k == '<' ? () => setState(() => _amount = '') : null,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 22)
                  : Text(
                      k,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keypad(double keyHeight) {
    Widget row(List<Widget> keys) => SizedBox(
      height: keyHeight,
      child: Row(children: keys),
    );
    return Column(
      children: [
        row([_padKey('1'), _padKey('2'), _padKey('3')]),
        row([_padKey('4'), _padKey('5'), _padKey('6')]),
        row([_padKey('7'), _padKey('8'), _padKey('9')]),
        row([
          _padKey('.'),
          _padKey('0'),
          _padKey('<', icon: Icons.backspace_outlined),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final cs = Theme.of(context).colorScheme;
    final accounts = repo.accounts
        .where((a) => !a.archived || a.id == _accountId || a.id == _toAccountId)
        .toList();
    final cats = repo.categories
        .where(
          (c) =>
              c.kind ==
              (_type == TxType.income ? TxType.income : TxType.expense),
        )
        .toList();
    final isTransfer = _type == TxType.transfer;
    final amountColor = switch (_type) {
      TxType.expense => Colors.red.shade400,
      TxType.income => Colors.green.shade600,
      TxType.transfer => cs.primary,
    };
    final dateLabel = dayOf(_date) == dayOf(DateTime.now())
        ? 'Today'
        : DateFormat('d MMM yy').format(_date);

    return Scaffold(
      resizeToAvoidBottomInset: false, // the page never reflows or scrolls
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add transaction' : 'Edit transaction',
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // Everything except the pad and the categories is roughly 266px.
            // Give categories at least ~130px; the pad shrinks on short screens.
            final keyH = ((box.maxHeight - 266 - 130) / 4).clamp(34.0, 46.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<TxType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TxType.expense,
                          label: Text('Expense'),
                        ),
                        ButtonSegment(
                          value: TxType.income,
                          label: Text('Income'),
                        ),
                        ButtonSegment(
                          value: TxType.transfer,
                          label: Text('Transfer'),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (s) => setState(() {
                        _type = s.first;
                        _categoryId = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Amount display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '₹ $_amountText',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          color: _amount.isEmpty
                              ? cs.onSurfaceVariant
                              : amountColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Accounts
                  if (isTransfer)
                    Row(
                      children: [
                        Expanded(
                          child: _accountDropdown(
                            accounts,
                            'From',
                            _accountId,
                            (v) => setState(() {
                              _accountId = v;
                              if (_toAccountId == v) _toAccountId = null;
                            }),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.arrow_forward, size: 18),
                        ),
                        Expanded(
                          child: _accountDropdown(
                            accounts.where((a) => a.id != _accountId).toList(),
                            'To',
                            _toAccountId,
                            (v) => setState(() => _toAccountId = v),
                            key: ValueKey('to-$_accountId'),
                          ),
                        ),
                      ],
                    )
                  else
                    _accountDropdown(
                      accounts,
                      'Account',
                      _accountId,
                      (v) => setState(() => _accountId = v),
                    ),
                  const SizedBox(height: 6),
                  // Categories fill whatever space is left; tags shrink to fit.
                  Expanded(
                    child: isTransfer
                        ? Center(
                            child: Text(
                              'Moves money between your accounts',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : _CategoryPicker(
                            categories: cats,
                            selectedId: _categoryId,
                            onSelect: (id) => setState(() => _categoryId = id),
                          ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _pill(Icons.event, dateLabel, _pickDate),
                      const SizedBox(width: 6),
                      _pill(
                        Icons.notes,
                        _note.isEmpty ? 'Note' : _note,
                        _editNote,
                        active: _note.isNotEmpty,
                      ),
                      const SizedBox(width: 6),
                      _pill(
                        _hasReceipt
                            ? Icons.receipt_long
                            : Icons.add_a_photo_outlined,
                        _hasReceipt ? 'Receipt ✓' : 'Receipt',
                        _receiptSheet,
                        active: _hasReceipt,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _keypad(keyH),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Save', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tier {
  final double height, font, hPad;
  final bool icon;
  const _Tier(this.height, this.font, this.hPad, this.icon);
}

/// Category tags that never scroll: it measures the labels, simulates the
/// wrap, and picks the largest tag size whose rows fit the available height.
class _CategoryPicker extends StatelessWidget {
  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  static const _tiers = [
    _Tier(36, 14, 12, true),
    _Tier(32, 13, 10, true),
    _Tier(28, 12, 9, true),
    _Tier(26, 11, 8, false),
    _Tier(23, 10, 6, false),
  ];
  static const _gap = 6.0, _runGap = 5.0, _iconW = 18.0, _slack = 4.0;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Center(
        child: Text('No categories. Add some in More → Categories.'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final base = DefaultTextStyle.of(context).style;
      double textWidth(String s, double font) {
        final p = TextPainter(
          text: TextSpan(
              text: s,
              style: base.copyWith(fontSize: font, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        return p.width;
      }

      double chipWidth(Category c, _Tier t) =>
            t.hPad * 2 +
            (t.icon ? _iconW : 0) +
            textWidth(c.name, t.font) +
            _slack;

        double heightFor(_Tier t) {
          var rows = 1;
          var x = 0.0;
          for (final c in categories) {
            final w = chipWidth(c, t).clamp(0, box.maxWidth).toDouble();
            if (x > 0 && x + _gap + w > box.maxWidth) {
              rows++;
              x = w;
            } else {
              x += (x > 0 ? _gap : 0) + w;
            }
          }
          return rows * t.height + (rows - 1) * _runGap;
        }

        var tier = _tiers.last;
        var fits = false;
        for (final t in _tiers) {
          if (heightFor(t) <= box.maxHeight) {
            tier = t;
            fits = true;
            break;
          }
        }

        final tags = Wrap(
          spacing: _gap,
          runSpacing: _runGap,
          children: [
            for (final c in categories)
              _Tag(
                category: c,
                tier: tier,
                selected: c.id == selectedId,
                cs: cs,
                onTap: () => onSelect(c.id),
              ),
          ],
        );
        // Normally everything fits without scrolling. Only if someone has so many
        // custom categories that even the smallest tags don't fit do we allow
        // this small area to scroll, so no category is ever unreachable.
        return fits
            ? Align(alignment: Alignment.topLeft, child: tags)
            : SingleChildScrollView(child: tags);
      },
    );
  }
}

class _Tag extends StatelessWidget {
  final Category category;
  final _Tier tier;
  final bool selected;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _Tag({
    required this.category,
    required this.tier,
    required this.selected,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? cs.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: tier.height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tier.hPad),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tier.icon) ...[
                  Icon(
                    category.iconData,
                    size: 14,
                    color: Color(category.color),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  category.name,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: tier.font,
                    fontWeight: FontWeight.w500,
                    color: selected ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
