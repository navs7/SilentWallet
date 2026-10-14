import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/repo.dart';
import '../services/lock.dart';
import '../util.dart';

class TxEditScreen extends StatefulWidget {
  final Tx? existing;
  const TxEditScreen({super.key, this.existing});
  @override
  State<TxEditScreen> createState() => _TxEditScreenState();
}

class _TxEditScreenState extends State<TxEditScreen> {
  final _form = GlobalKey<FormState>();
  late TxType _type;
  late TextEditingController _amount;
  late TextEditingController _note;
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
    _amount = TextEditingController(
        text: t == null ? '' : (t.amount / 100).toStringAsFixed(2));
    _note = TextEditingController(text: t?.note ?? '');
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

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt(ImageSource src) async {
    final lock = context.read<LockController>();
    final x = await lock.suspendLock(() => ImagePicker()
        .pickImage(source: src, maxWidth: 1600, imageQuality: 75));
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

  void _receiptSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take photo'),
            onTap: () {
              Navigator.pop(context);
              _pickReceipt(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickReceipt(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_accountId == null) {
      toast(context, 'Create an account first (Accounts tab).');
      return;
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
    final t = Tx(
      id: old?.id ?? newId(),
      type: _type,
      amount: parseAmount(_amount.text)!,
      accountId: _accountId!,
      toAccountId: _type == TxType.transfer ? _toAccountId : null,
      categoryId: _type == TxType.transfer ? null : _categoryId,
      note: _note.text.trim(),
      date: _date,
      receipt: receipt,
      recurringId: old?.recurringId,
    );
    await repo.saveTx(t);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete transaction?', 'This cannot be undone.')) return;
    if (!mounted) return;
    await context.read<Repo>().deleteTx(widget.existing!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final accounts = repo.accounts
        .where((a) => !a.archived || a.id == _accountId || a.id == _toAccountId)
        .toList();
    final cats = repo.categories
        .where((c) => c.kind == (_type == TxType.income ? TxType.income : TxType.expense))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add transaction' : 'Edit transaction'),
        actions: [
          if (widget.existing != null)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('Expense')),
              ButtonSegment(value: TxType.income, label: Text('Income')),
              ButtonSegment(value: TxType.transfer, label: Text('Transfer')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            autofocus: widget.existing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Amount'),
            validator: (v) => parseAmount(v ?? '') == null ? 'Enter an amount' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: InputDecoration(
                labelText: _type == TxType.transfer ? 'From account' : 'Account'),
            items: [
              for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))
            ],
            onChanged: (v) => setState(() {
              _accountId = v;
              if (_toAccountId == v) _toAccountId = null;
            }),
            validator: (v) => v == null ? 'Choose an account' : null,
          ),
          if (_type == TxType.transfer) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('to-$_accountId'),
              initialValue: _toAccountId,
              decoration: const InputDecoration(labelText: 'To account'),
              items: [
                for (final a in accounts.where((a) => a.id != _accountId))
                  DropdownMenuItem(value: a.id, child: Text(a.name))
              ],
              onChanged: (v) => setState(() => _toAccountId = v),
              validator: (v) => v == null ? 'Choose the destination account' : null,
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: Icon(c.iconData, size: 18, color: Color(c.color)),
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (_) => setState(() => _categoryId = c.id),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) {
                setState(() => _date = DateTime(d.year, d.month, d.day,
                    _date.hour, _date.minute));
              }
            },
          ),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          if (_receiptPreview != null && !_receiptRemoved)
            Stack(alignment: Alignment.topRight, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_receiptPreview!, height: 220, width: double.infinity, fit: BoxFit.cover),
              ),
              IconButton.filledTonal(
                onPressed: () => setState(() {
                  _receiptRemoved = true;
                  _newReceipt = null;
                  _receiptPreview = null;
                }),
                icon: const Icon(Icons.close),
              ),
            ])
          else
            OutlinedButton.icon(
              onPressed: _receiptSheet,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Attach receipt photo'),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Save')),
          ),
        ]),
      ),
    );
  }
}
