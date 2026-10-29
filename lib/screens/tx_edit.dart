import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../core/calc.dart';
import '../core/models.dart';
import '../core/repo.dart';
import '../core/search.dart';
import '../services/lock.dart';
import '../theme.dart';
import '../util.dart';
import 'amount_pad.dart';

/// Add / edit transaction. The amount is typed on an in-app calculator keypad;
/// its Done key moves on to the note with the phone keyboard open, and the page
/// scrolls so the note, date, receipt and Save stay above that keyboard. With no
/// keyboard showing the page is a fixed layout and the category tags resize to
/// fit whatever height is left.
class TxEditScreen extends StatefulWidget {
  final Tx? existing;

  /// Start a NEW entry pre-filled from this one (the Copy button).
  final Tx? copyOf;
  const TxEditScreen({super.key, this.existing, this.copyOf});
  @override
  State<TxEditScreen> createState() => _TxEditScreenState();
}

class _TxEditScreenState extends State<TxEditScreen> {
  late TxType _type;
  final _amountCtl = TextEditingController();
  final _amountFocus = FocusNode();
  final _scroll = ScrollController();
  bool _padOpen = false; // in-app amount keypad showing
  int _gst = 5; // GST rate on the calculator key (long-press switches 5 <-> 18)
  bool _calc = false; // calculator row shown on the keypad
  Frequency? _repeat; // null = does not repeat (new entries only)
  DateTime? _repeatEnd; // optional last date of the repeat
  final _noteCtl = TextEditingController();
  final _noteFocus = FocusNode();
  final _commentCtl = TextEditingController();
  final _commentFocus = FocusNode();
  List<NoteEntry> _history = []; // notes used before, for suggestions
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
    // Editing fills the page from the entry; copying fills it from the copy
    // draft (but it is saved as a new entry, dated today, without a receipt).
    final t = widget.existing ?? widget.copyOf;
    final repo = context.read<Repo>();
    _type = t?.type ?? TxType.expense;
    _padOpen = t == null; // new transaction: start on the amount keypad
    _amountFocus.addListener(_onAmountFocus);
    _noteFocus.addListener(_onNoteFocus);
    _commentFocus.addListener(_onNoteFocus);
    if (t != null && t.amount > 0) {
      var s = (t.amount / 100).toStringAsFixed(2);
      if (s.endsWith('.00')) {
        s = s.substring(0, s.length - 3);
      } else if (s.endsWith('0')) {
        s = s.substring(0, s.length - 1);
      }
      _amountCtl.text = s;
    }
    _noteCtl.text = t?.note ?? '';
    _commentCtl.text = t?.comment ?? '';
    _categoryId = t?.categoryId;
    // New transactions start on the account marked as default.
    _accountId = t?.accountId ?? defaultAccountId(repo.accounts);
    repo.noteHistory().then((h) {
      if (mounted) setState(() => _history = h);
    });
    _toAccountId = t?.toAccountId;
    _date = widget.existing?.date ?? DateTime.now();
    _receiptName = widget.existing?.receipt;
    if (_receiptName != null) {
      repo.readReceipt(_receiptName!).then((b) {
        if (mounted) setState(() => _receiptPreview = b);
      });
    }
  }

  @override
  void dispose() {
    _amountFocus.removeListener(_onAmountFocus);
    _noteFocus.removeListener(_onNoteFocus);
    _commentFocus.removeListener(_onNoteFocus);
    _noteCtl.dispose();
    _noteFocus.dispose();
    _commentCtl.dispose();
    _commentFocus.dispose();
    _amountCtl.dispose();
    _amountFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onAmountFocus() {
    if (!mounted) return;
    if (_amountFocus.hasFocus) setState(() => _padOpen = true);
  }

  void _onNoteFocus() {
    if (!mounted) return;
    if (_noteFocus.hasFocus || _commentFocus.hasFocus) {
      setState(() => _padOpen = false);
    }
  }

  // ---------- amount ----------
  int? get _amountPaise => AmountEntry(_amountCtl.text).paise;

  void _setAmountText(String t) {
    _amountCtl.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  void _press(String key) {
    final e = AmountEntry(_amountCtl.text)..press(key);
    _setAmountText(e.text);
  }

  void _addGst() {
    final e = AmountEntry(_amountCtl.text);
    if (e.addPercent(_gst)) {
      _setAmountText(e.text);
    } else {
      toast(context, 'Enter an amount first.');
    }
  }

  void _equals() {
    final e = AmountEntry(_amountCtl.text);
    if (e.equals()) {
      _setAmountText(e.text);
    } else if (e.hasOperator) {
      toast(context, 'Complete the calculation first.');
    }
  }

  void _closePad() {
    setState(() => _padOpen = false);
    _amountFocus.unfocus();
  }

  /// Done: work out any calculation, then go to the note with the phone
  /// keyboard open (the page scrolls so the note and Save sit above it).
  void _amountDone() {
    final e = AmountEntry(_amountCtl.text);
    if (e.paise == null) {
      toast(context, 'Enter an amount greater than 0.');
      return;
    }
    if (e.hasOperator) _setAmountText(formatAmount(e.value!));
    setState(() => _padOpen = false);
    _amountFocus.unfocus();
    // The note field only exists once the keypad is gone, so focus it after
    // the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _noteFocus.requestFocus();
    });
  }

  // ---------- note / date / receipt ----------
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

  // ---------- repeat ----------
  void _repeatSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final fmt = DateFormat('d MMM yyyy');
          final cs = Theme.of(ctx).colorScheme;
          void choose(Frequency? f) {
            setState(() {
              _repeat = f;
              if (f == null) _repeatEnd = null;
            });
            set(() {});
          }

          final first = dayOf(_date);
          final next = _repeat == null
              ? null
              : nextOccurrence(first, _repeat!, anchorDay: first.day);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Repeat', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Saves this entry now and adds it again on each date.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        key: const Key('repeat-none'),
                        label: const Text('Does not repeat'),
                        selected: _repeat == null,
                        onSelected: (_) => choose(null),
                      ),
                      for (final f in Frequency.values)
                        ChoiceChip(
                          key: Key('repeat-${f.name}'),
                          label: Text(toBeginningOfSentenceCase(f.name)!),
                          selected: _repeat == f,
                          onSelected: (_) => choose(f),
                        ),
                    ],
                  ),
                  if (_repeat != null) ...[
                    const SizedBox(height: 8),
                    ListTile(
                      key: const Key('repeat-end'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_busy),
                      title: Text(
                        _repeatEnd == null
                            ? 'Ends: never'
                            : 'Ends ${fmt.format(_repeatEnd!)}',
                      ),
                      trailing: _repeatEnd == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() => _repeatEnd = null);
                                set(() {});
                              },
                            ),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: _repeatEnd ?? next!,
                          firstDate: first,
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (d != null) {
                          setState(() => _repeatEnd = dayOf(d));
                          set(() {});
                        }
                      },
                    ),
                    Text(
                      'Next one: ${fmt.format(next!)}'
                      '${next.isAfter(dayOf(DateTime.now())) ? '' : ' — entries up to today will be added automatically'}',
                      key: const Key('repeat-next'),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('repeat-done'),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- save / delete ----------
  Future<void> _save() async {
    final amt = _amountPaise;
    if (amt == null) return toast(context, 'Enter an amount.');
    if (_accountId == null) {
      return toast(context, 'Create an account first (Manage tab).');
    }
    if (_type == TxType.transfer && _toAccountId == null) {
      return toast(context, 'Choose the destination account.');
    }
    setState(() => _saving = true);
    final repo = context.read<Repo>();
    final old = widget.existing;
    // No category chosen: file it under "Other" instead of "Uncategorized".
    final categoryId = _type == TxType.transfer
        ? null
        : (_categoryId ?? await repo.otherCategoryId(_type));
    String? receipt = _receiptName;
    if (_newReceipt != null) {
      receipt = await repo.saveReceipt(_newReceipt!);
      if (old?.receipt != null) await repo.deleteReceipt(old!.receipt!);
    } else if (_receiptRemoved) {
      if (old?.receipt != null) await repo.deleteReceipt(old!.receipt!);
      receipt = null;
    }
    // Repeat: besides this entry, create a recurring rule that carries on
    // from the next date (the existing recurring engine adds the later ones).
    String? ruleId;
    if (old == null && _repeat != null && _type != TxType.transfer) {
      final first = dayOf(_date);
      final note = _noteCtl.text.trim();
      ruleId = newId();
      await repo.saveRecurring(
        Recurring(
          id: ruleId,
          title: note.isNotEmpty
              ? note
              : (repo.category(categoryId)?.name ?? 'Recurring'),
          type: _type,
          amount: amt,
          accountId: _accountId!,
          categoryId: categoryId,
          frequency: _repeat!,
          nextDue: nextOccurrence(first, _repeat!, anchorDay: first.day),
          anchorDay: first.day,
          endDate: _repeatEnd,
        ),
      );
    }
    await repo.saveTx(
      Tx(
        id: old?.id ?? newId(),
        type: _type,
        amount: amt,
        accountId: _accountId!,
        toAccountId: _type == TxType.transfer ? _toAccountId : null,
        categoryId: categoryId,
        note: _noteCtl.text.trim(),
        comment: _commentCtl.text.trim(),
        date: _date,
        receipt: receipt,
        recurringId: ruleId ?? old?.recurringId,
      ),
    );
    if (ruleId != null && mounted) {
      toast(
        context,
        'Saved. Repeats ${_repeat!.name} — manage it in More → Recurring.',
      );
    }
    if (mounted) Navigator.pop(context);
  }

  /// Copy: open a NEW entry pre-filled with what is on screen (amount, account,
  /// category, note, comment). It is dated today and has no receipt; the
  /// original is left as it was saved.
  void _copy() {
    final draft = Tx(
      id: newId(),
      type: _type,
      amount: _amountPaise ?? 0,
      accountId: _accountId ?? widget.existing!.accountId,
      toAccountId: _type == TxType.transfer ? _toAccountId : null,
      categoryId: _type == TxType.transfer ? null : _categoryId,
      note: _noteCtl.text.trim(),
      comment: _commentCtl.text.trim(),
      date: DateTime.now(),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => TxEditScreen(copyOf: draft)),
    );
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
  /// The category area: stretches to fill the page normally, but takes just the
  /// natural height of its tags while the phone keyboard is open (no empty gap).
  Widget _catsSlot(bool compact, Widget child) =>
      compact ? child : Expanded(child: child);

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

  /// Note box with suggestions from earlier notes (shown above the field).
  Widget _noteField(List<Category> cats) {
    final cs = Theme.of(context).colorScheme;
    return RawAutocomplete<NoteEntry>(
      textEditingController: _noteCtl,
      focusNode: _noteFocus,
      optionsViewOpenDirection: OptionsViewOpenDirection.up,
      displayStringForOption: (e) => e.note,
      optionsBuilder: (v) => rankNotes(_history, v.text, limit: 30),
      onSelected: (e) {
        // Re-use the category this note had last time, if none is chosen yet.
        if (_categoryId == null &&
            _type != TxType.transfer &&
            e.categoryId != null &&
            cats.any((c) => c.id == e.categoryId)) {
          setState(() => _categoryId = e.categoryId);
        }
      },
      fieldViewBuilder: (context, ctl, focus, onSubmit) => SizedBox(
        height: 42,
        child: TextField(
          key: const Key('note-field'),
          controller: ctl,
          focusNode: focus,
          maxLines: 1,
          keyboardType: TextInputType.text, // normal keyboard for notes
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 15),
          onSubmitted: (_) => _commentFocus.requestFocus(),
          onTapOutside: (_) => focus.unfocus(),
          decoration: const InputDecoration(
            hintText: 'Add a note',
            prefixIcon: Icon(Icons.notes, size: 18),
            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 34),
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.bottomLeft,
        child: Material(
          elevation: 4,
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 4.5 * 44.0, // fixed area; scroll for more
              maxWidth: MediaQuery.sizeOf(context).width - 24,
            ),
            child: ListView.builder(
              key: const Key('note-suggestions'),
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemExtent: 44,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final e = options.elementAt(i);
                return InkWell(
                  onTap: () => onSelected(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            e.note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final cs = Theme.of(context).colorScheme;
    final accounts = accountsDefaultFirst(
      repo.accounts
          .where(
            (a) => !a.archived || a.id == _accountId || a.id == _toAccountId,
          )
          .toList(),
    );
    final cats = repo.categories
        .where(
          (c) =>
              c.kind ==
              (_type == TxType.income ? TxType.income : TxType.expense),
        )
        .toList();
    final isTransfer = _type == TxType.transfer;
    // Repeat is offered for new income / expense entries only.
    final canRepeat = !isTransfer && widget.existing == null;
    final amountColor = switch (_type) {
      TxType.expense => Colors.red.shade400,
      TxType.income => Colors.green.shade600,
      TxType.transfer => cs.primary,
    };
    final dateLabel = dayOf(_date) == dayOf(DateTime.now())
        ? 'Today'
        : DateFormat('d MMM yy').format(_date);

    final showPad = _padOpen;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing != null
              ? 'Edit transaction'
              : (widget.copyOf != null
                    ? 'Copy transaction'
                    : 'Add transaction'),
        ),
        actions: [
          if (widget.existing != null) ...[
            IconButton(
              key: const Key('copy-button'),
              tooltip: 'Copy transaction',
              onPressed: _copy,
              icon: const Icon(Icons.content_copy_outlined),
            ),
            IconButton(
              key: const Key('delete-button'),
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            // No phone keyboard: a fixed layout that does not scroll. With the
            // phone keyboard open (note / phone-keyboard amount) the same
            // layout becomes scrollable.
            final view = View.of(context);
            final keyboard = view.viewInsets.bottom / view.devicePixelRatio;
            final navBar = view.padding.bottom / view.devicePixelRatio;
            final fullH =
                box.maxHeight + (keyboard > 0 ? keyboard - navBar : 0);
            // While the phone keyboard is open the page uses the content's natural
            // height: the category area shrinks to its tags instead of stretching,
            // so there is no empty gap above the note.
            final compact = keyboard > 0;
            final padRows = _calc ? 5 : 4;
            // Everything above the keypad is ~190px; keep >=130px for tags.
            final rowH = ((fullH - 190 - 130 - 44) / padRows).clamp(38.0, 50.0);
            final padH = showPad ? AmountPad.heightFor(rowH, _calc) : 0.0;
            if (keyboard > 0 &&
                (_noteFocus.hasFocus || _commentFocus.hasFocus)) {
              // Scroll up so note, date, receipt and Save sit above the keyboard.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
            return SingleChildScrollView(
              controller: _scroll,
              physics: keyboard > 0
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: compact ? null : fullH - padH,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: Column(
                        mainAxisSize: compact
                            ? MainAxisSize.min
                            : MainAxisSize.max,
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
                                if (_type == TxType.transfer) {
                                  _repeat = null;
                                  _repeatEnd = null;
                                }
                              }),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Amount (typed on the in-app keypad)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  key: const Key('amount-field'),
                                  controller: _amountCtl,
                                  focusNode: _amountFocus,
                                  autofocus:
                                      widget.existing == null &&
                                      widget.copyOf == null,
                                  readOnly: true,
                                  showCursor: true,
                                  enableInteractiveSelection: false,
                                  keyboardType: TextInputType
                                      .none, // the in-app keypad is used
                                  textInputAction: TextInputAction.done,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.5,
                                    fontFeatures: kTabularFigures,
                                    color: amountColor,
                                  ),
                                  decoration: InputDecoration(
                                    prefixText: '₹ ',
                                    prefixStyle: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    hintText: '0',
                                    hintStyle: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                                // live result while a calculation is typed
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _amountCtl,
                                  builder: (context, v, _) {
                                    final e = AmountEntry(v.text);
                                    final r = e.hasOperator ? e.value : null;
                                    if (r == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          key: const Key('amount-result'),
                                          '= ₹ ${formatAmount(r)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
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
                                      if (_toAccountId == v) {
                                        _toAccountId = null;
                                      }
                                    }),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.arrow_forward, size: 18),
                                ),
                                Expanded(
                                  child: _accountDropdown(
                                    accounts
                                        .where((a) => a.id != _accountId)
                                        .toList(),
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
                          const SizedBox(height: 16),
                          // Categories fill whatever space is left; tags shrink to fit.
                          _catsSlot(
                            compact,
                            isTransfer
                                ? Center(
                                    child: Text(
                                      'Moves money between your accounts',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : _CategoryPicker(
                                    categories: cats,
                                    selectedId: _categoryId,
                                    onSelect: (id) =>
                                        setState(() => _categoryId = id),
                                  ),
                          ),
                          if (!showPad) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(child: _noteField(cats)),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: _pickDate,
                                  icon: const Icon(Icons.event, size: 16),
                                  label: Text(dateLabel),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 42),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: _hasReceipt
                                      ? 'Receipt attached'
                                      : 'Attach receipt',
                                  child: OutlinedButton(
                                    onPressed: _receiptSheet,
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(44, 42),
                                      padding: EdgeInsets.zero,
                                      backgroundColor: _hasReceipt
                                          ? cs.primaryContainer
                                          : null,
                                    ),
                                    child: Icon(
                                      _hasReceipt
                                          ? Icons.receipt_long
                                          : Icons.add_a_photo_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                if (canRepeat) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: _repeat == null
                                        ? 'Repeat'
                                        : 'Repeats ${_repeat!.name}',
                                    child: OutlinedButton(
                                      key: const Key('repeat-button'),
                                      onPressed: _repeatSheet,
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(44, 42),
                                        padding: EdgeInsets.zero,
                                        backgroundColor: _repeat != null
                                            ? cs.primaryContainer
                                            : null,
                                      ),
                                      child: const Icon(Icons.repeat, size: 20),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('comment-field'),
                              controller: _commentCtl,
                              focusNode: _commentFocus,
                              minLines: 1,
                              maxLines: 3,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(fontSize: 15),
                              onTapOutside: (_) => _commentFocus.unfocus(),
                              decoration: const InputDecoration(
                                hintText: 'Add a comment (optional)',
                                prefixIcon: Icon(
                                  Icons.chat_bubble_outline,
                                  size: 18,
                                ),
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: 34,
                                  minHeight: 34,
                                ),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: FilledButton(
                                onPressed: _saving ? null : _save,
                                child: const Text(
                                  'Save',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (showPad)
                    AmountPad(
                      calculator: _calc,
                      rowHeight: rowH,
                      onKey: _press,
                      onDone: _amountDone,
                      onEquals: _equals,
                      gstPercent: _gst,
                      onGst: _addGst,
                      onGstRate: () =>
                          setState(() => _gst = _gst == 5 ? 18 : 5),
                      onClose: _closePad,
                      onToggleCalculator: () => setState(() => _calc = !_calc),
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

const _tagTiers = [
  _Tier(36, 14, 12, true),
  _Tier(32, 13, 10, true),
  _Tier(28, 12, 9, true),
  _Tier(26, 11, 8, false),
  _Tier(23, 10, 6, false),
];
const _tagGap = 6.0, _tagRunGap = 5.0, _tagIconW = 18.0, _tagSlack = 4.0;

class _TagPlan {
  final _Tier tier;
  final double height;
  final bool fits;
  const _TagPlan(this.tier, this.height, this.fits);
}

/// Measures the labels, simulates the wrap and picks the largest tag size whose
/// rows fit [maxHeight]. Pass `double.infinity` for the natural (biggest) size.
_TagPlan _planTags(
  BuildContext context,
  List<Category> categories,
  double maxWidth,
  double maxHeight,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final base = DefaultTextStyle.of(context).style;

  double textWidth(String s, double font) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: base.copyWith(fontSize: font, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return p.width;
  }

  double heightFor(_Tier t) {
    var rows = 1;
    var x = 0.0;
    for (final c in categories) {
      final w =
          (t.hPad * 2 +
                  (t.icon ? _tagIconW : 0) +
                  textWidth(c.name, t.font) +
                  _tagSlack)
              .clamp(0, maxWidth)
              .toDouble();
      if (x > 0 && x + _tagGap + w > maxWidth) {
        rows++;
        x = w;
      } else {
        x += (x > 0 ? _tagGap : 0) + w;
      }
    }
    return rows * t.height + (rows - 1) * _tagRunGap;
  }

  for (final t in _tagTiers) {
    final h = heightFor(t);
    if (h <= maxHeight) return _TagPlan(t, h, true);
  }
  final last = _tagTiers.last;
  return _TagPlan(last, heightFor(last), false);
}

/// Category tags that never scroll: they use the largest tag size that fits the
/// space they are given.
class _CategoryPicker extends StatelessWidget {
  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Center(
        child: Text('No categories. Add some in More → Categories.'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final plan = _planTags(
          context,
          categories,
          box.maxWidth,
          box.maxHeight,
        );
        final tags = Wrap(
          spacing: _tagGap,
          runSpacing: _tagRunGap,
          children: [
            for (final c in categories)
              _Tag(
                category: c,
                tier: plan.tier,
                selected: c.id == selectedId,
                cs: cs,
                onTap: () => onSelect(c.id),
              ),
          ],
        );
        // Normally everything fits without scrolling. Only if someone has so many
        // custom categories that even the smallest tags don't fit do we allow
        // this small area to scroll, so no category is ever unreachable.
        return plan.fits
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
                    size: kCategoryIconSize,
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
