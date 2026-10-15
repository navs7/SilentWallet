import 'models.dart';

/// Does [t] match [query]? Every word of the query must appear somewhere in
/// the note, category, account name(s) or amount (e.g. 150 or 150.50).
bool txMatches(
  Tx t,
  String query, {
  String? accountName,
  String? toAccountName,
  String? categoryName,
}) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final rupees = t.amount / 100;
  final plain = rupees.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  final hay = [
    t.note,
    categoryName,
    accountName,
    toAccountName,
    rupees.toStringAsFixed(2),
    plain,
  ].whereType<String>().join(' ').toLowerCase();
  return words.every(hay.contains);
}

/// One distinct note the user has used before.
class NoteEntry {
  final String note;
  final int count;
  final DateTime last;
  final String? categoryId; // category of the most recent use
  const NoteEntry(this.note, this.count, this.last, this.categoryId);
}

/// Groups raw notes (ignoring case and surrounding spaces) into a history.
/// The text keeps the spelling of its most recent use.
List<NoteEntry> buildNoteHistory(
  Iterable<({String note, String? categoryId, DateTime date})> rows,
) {
  final byKey = <String, NoteEntry>{};
  for (final r in rows) {
    final text = r.note.trim();
    if (text.isEmpty) continue;
    final key = text.toLowerCase();
    final old = byKey[key];
    if (old == null) {
      byKey[key] = NoteEntry(text, 1, r.date, r.categoryId);
    } else if (r.date.isAfter(old.last)) {
      byKey[key] = NoteEntry(text, old.count + 1, r.date, r.categoryId);
    } else {
      byKey[key] = NoteEntry(old.note, old.count + 1, old.last, old.categoryId);
    }
  }
  return byKey.values.toList();
}

/// Suggestions for what the user is typing. With no text: most recent first.
/// With text: notes that start with it, then notes that contain it; within
/// each group the most used, then the most recent. An exact match is not
/// suggested back.
List<NoteEntry> rankNotes(List<NoteEntry> all, String query, {int limit = 6}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    final recent = [...all]..sort((a, b) => b.last.compareTo(a.last));
    return recent.take(limit).toList();
  }
  int byUse(NoteEntry a, NoteEntry b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : b.last.compareTo(a.last);
  }

  final starts = <NoteEntry>[], contains = <NoteEntry>[];
  for (final e in all) {
    final n = e.note.toLowerCase();
    if (n == q) continue;
    if (n.startsWith(q)) {
      starts.add(e);
    } else if (n.contains(q)) {
      contains.add(e);
    }
  }
  starts.sort(byUse);
  contains.sort(byUse);
  return [...starts, ...contains].take(limit).toList();
}

/// Optional filters applied together with the search text.
class SearchFilters {
  /// Time period: [from] inclusive, [to] exclusive.
  DateTime? from;
  DateTime? to;
  String? periodKey; // 'month' | 'last' | 'year' | 'custom' (for the UI)
  String? periodLabel;
  String? accountId;
  String? categoryId;
  int? minPaise; // inclusive
  int? maxPaise; // inclusive

  SearchFilters({
    this.from,
    this.to,
    this.periodKey,
    this.periodLabel,
    this.accountId,
    this.categoryId,
    this.minPaise,
    this.maxPaise,
  });

  bool get hasPeriod => from != null && to != null;
  bool get hasAmount => minPaise != null || maxPaise != null;

  bool get isActive =>
      hasPeriod || accountId != null || categoryId != null || hasAmount;

  SearchFilters copy() => SearchFilters(
    from: from,
    to: to,
    periodKey: periodKey,
    periodLabel: periodLabel,
    accountId: accountId,
    categoryId: categoryId,
    minPaise: minPaise,
    maxPaise: maxPaise,
  );

  void clearPeriod() {
    from = to = null;
    periodKey = periodLabel = null;
  }

  void clearAmount() {
    minPaise = maxPaise = null;
  }

  bool matches(Tx t) {
    if (hasPeriod && (t.date.isBefore(from!) || !t.date.isBefore(to!))) {
      return false;
    }
    if (accountId != null &&
        t.accountId != accountId &&
        t.toAccountId != accountId) {
      return false;
    }
    if (categoryId != null && t.categoryId != categoryId) return false;
    if (minPaise != null && t.amount < minPaise!) return false;
    if (maxPaise != null && t.amount > maxPaise!) return false;
    return true;
  }
}
