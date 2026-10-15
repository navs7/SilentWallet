import 'dart:math';

/// Seven short, quirky messages for the daily "add today's entries" reminder.
const reminderMessages = <String>[
  "Your wallet misses you. Log today's spending! 💸",
  "Psst… today's expenses are hiding. Find them! 🕵️",
  'Future you wants today on record. Add it now! 📞',
  'Chai, snacks, autos… the small ones count too ☕',
  'Plot twist: you remember every rupee. Add them! 🎬',
  "Beat the midnight bell: add today's entries ⏰",
  'One tiny minute now saves a month-end headache 🧠',
];

/// The message for [day]. Every block of 7 days shows each message exactly
/// once, in a random order that differs from block to block, and the same
/// message is never shown on two days in a row. It is fixed for a given day
/// and [seed] (so re-planning the reminders never changes tomorrow's text),
/// while a different [seed] (one per install) gives a different order.
String reminderMessageFor(DateTime day, {int seed = 0}) {
  final n = reminderMessages.length;
  final d = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(1970)).inDays;
  final block = d ~/ n;
  final pos = d % n;
  final order = _blockOrder(block, seed);
  return reminderMessages[order[pos]];
}

List<int> _rawOrder(int block, int seed) {
  final order = List<int>.generate(reminderMessages.length, (i) => i);
  order.shuffle(Random(seed * 1000003 + block * 7919 + 17));
  return order;
}

List<int> _blockOrder(int block, int seed) {
  final order = _rawOrder(block, seed);
  if (block > 0) {
    final previousLast = _rawOrder(block - 1, seed).last;
    // keep the first day of this block different from the last day of the
    // previous one (a swap of the first two never changes a block's last)
    if (order.first == previousLast) {
      final t = order[0];
      order[0] = order[1];
      order[1] = t;
    }
  }
  return order;
}
