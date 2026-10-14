import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String money(int paise, {bool compact = false}) =>
    (compact && paise % 100 == 0 ? _inr0 : _inr).format(paise / 100);

/// Parses "1,234.50" into paise. Returns null if invalid / not positive.
int? parseAmount(String s) {
  final v = double.tryParse(s.replaceAll(',', '').trim());
  if (v == null || v <= 0 || v > 1e11) return null;
  return (v * 100).round();
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String dayLabel(DateTime d) {
  final today = dayOf(DateTime.now());
  final diff = today.difference(dayOf(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM yyyy').format(d);
}

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext c, String title, String body,
    {String ok = 'Delete'}) async {
  return await showDialog<bool>(
        context: c,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ??
      false;
}

Future<String?> askPassword(BuildContext c,
    {required String title, String? hint, bool confirmField = false}) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: c,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hint != null)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(hint)),
          TextField(
            controller: a,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (confirmField)
            TextField(
              controller: b,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat password'),
            ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (confirmField) {
                if (a.text.length < 6) {
                  set(() => err = 'Use at least 6 characters.');
                  return;
                }
                if (a.text != b.text) {
                  set(() => err = 'Passwords do not match.');
                  return;
                }
              } else if (a.text.isEmpty) {
                return;
              }
              Navigator.pop(ctx, a.text);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

class DateRange {
  final DateTime from; // inclusive
  final DateTime to; // exclusive
  final String label;
  const DateRange(this.from, this.to, this.label);
}

DateRange monthRange(DateTime m) => DateRange(
      DateTime(m.year, m.month),
      DateTime(m.year, m.month + 1),
      DateFormat('MMMM yyyy').format(m),
    );
