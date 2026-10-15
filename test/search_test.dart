import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/search.dart';

import 'test_support.dart';

void main() {
  final day = DateTime(2026, 3, 10);

  group('txMatches', () {
    final t = sampleTx('1', day, note: 'Dinner at Zomato', paise: 25050);

    test('matches the note, ignoring case', () {
      expect(txMatches(t, 'zomato'), isTrue);
      expect(txMatches(t, 'DINNER'), isTrue);
      expect(txMatches(t, 'uber'), isFalse);
    });

    test('matches category and account names', () {
      expect(txMatches(t, 'groceries', categoryName: 'Groceries'), isTrue);
      expect(txMatches(t, 'hdfc', accountName: 'HDFC Savings'), isTrue);
      expect(txMatches(t, 'icici', toAccountName: 'ICICI'), isTrue);
      expect(txMatches(t, 'groceries'), isFalse);
    });

    test('matches the amount in rupees', () {
      expect(txMatches(t, '250.50'), isTrue);
      expect(txMatches(t, '250'), isTrue);
      expect(txMatches(sampleTx('2', day, paise: 15000), '150'), isTrue);
      expect(txMatches(sampleTx('2', day, paise: 15000), '999'), isFalse);
    });

    test('every word must match somewhere', () {
      expect(txMatches(t, 'zomato dinner'), isTrue);
      expect(txMatches(t, 'zomato lunch'), isFalse);
      expect(txMatches(t, 'zomato groceries', categoryName: 'Groceries'), isTrue);
    });

    test('blank query matches everything', () {
      expect(txMatches(t, ''), isTrue);
      expect(txMatches(t, '   '), isTrue);
    });
  });

  group('note history', () {
    row(String n, DateTime d, [String? c]) => (note: n, categoryId: c, date: d);

    test('groups notes ignoring case and spaces, counting uses', () {
      final h = buildNoteHistory([
        row('Zomato', DateTime(2026, 1, 1), 'c1'),
        row('  zomato ', DateTime(2026, 2, 1), 'c2'),
        row('ZOMATO', DateTime(2026, 1, 15), 'c3'),
        row('Uber', DateTime(2026, 1, 5)),
        row('   ', DateTime(2026, 1, 6)),
        row('', DateTime(2026, 1, 7)),
      ]);
      expect(h.length, 2);
      final z = h.firstWhere((e) => e.note.toLowerCase() == 'zomato');
      expect(z.count, 3);
      expect(z.last, DateTime(2026, 2, 1));
      expect(z.note, 'zomato'); // spelling of the most recent use, trimmed
      expect(z.categoryId, 'c2'); // category of the most recent use
    });
  });

  group('rankNotes', () {
    final all = [
      NoteEntry('Zomato dinner', 5, DateTime(2026, 1, 1), 'c1'),
      NoteEntry('Zomato lunch', 2, DateTime(2026, 3, 1), 'c1'),
      NoteEntry('Order from Zomato', 9, DateTime(2026, 2, 1), 'c1'),
      NoteEntry('Uber ride', 3, DateTime(2026, 2, 15), 'c2'),
      NoteEntry('Metro card', 1, DateTime(2026, 3, 9), 'c2'),
    ];

    test('empty query: most recent first', () {
      expect(rankNotes(all, '').map((e) => e.note).toList(),
          ['Metro card', 'Zomato lunch', 'Uber ride', 'Order from Zomato', 'Zomato dinner']);
    });

    test('starts-with beats contains, then most used', () {
      expect(rankNotes(all, 'zom').map((e) => e.note).toList(),
          ['Zomato dinner', 'Zomato lunch', 'Order from Zomato']);
    });

    test('contains matches in the middle of a note', () {
      expect(rankNotes(all, 'rid').map((e) => e.note).toList(), ['Uber ride']);
    });

    test('an exact match is not suggested back', () {
      expect(rankNotes(all, 'uber ride'), isEmpty);
      expect(rankNotes(all, 'ZOMATO DINNER'), isEmpty);
    });

    test('respects the limit and handles no matches', () {
      expect(rankNotes(all, '', limit: 2).length, 2);
      expect(rankNotes(all, 'xyz'), isEmpty);
      expect(rankNotes(const [], 'a'), isEmpty);
    });
  });

  group('default account', () {
    Account acc(String id, String name, {bool def = false, bool archived = false}) =>
        Account(id: id, name: name, type: 'Bank', isDefault: def, archived: archived);

    test('uses the account marked default', () {
      expect(defaultAccountId([acc('a', 'Axis'), acc('b', 'Cash', def: true), acc('c', 'HDFC')]), 'b');
    });

    test('falls back to the first active account', () {
      expect(defaultAccountId([acc('a', 'Axis', archived: true), acc('b', 'Cash')]), 'b');
      expect(defaultAccountId([acc('a', 'Axis'), acc('b', 'Cash')]), 'a');
    });

    test('an archived default is ignored', () {
      expect(defaultAccountId([acc('a', 'Axis'), acc('b', 'Cash', def: true, archived: true)]), 'a');
    });

    test('no accounts / all archived gives null', () {
      expect(defaultAccountId([]), isNull);
      expect(defaultAccountId([acc('a', 'Axis', archived: true)]), isNull);
    });

    test('picker lists the default first and keeps the rest in order', () {
      final out = accountsDefaultFirst(
          [acc('a', 'Axis'), acc('b', 'Cash'), acc('c', 'HDFC', def: true)]);
      expect(out.map((a) => a.id).toList(), ['c', 'a', 'b']);
    });

    test('a new account named "Axis" does not jump ahead of the default', () {
      // alphabetical order would put Axis first; the default still wins
      final accounts = [acc('new', 'Axis'), acc('cash', 'Cash', def: true)];
      expect(defaultAccountId(accounts), 'cash');
      expect(accountsDefaultFirst(accounts).first.id, 'cash');
    });

    test('is_default is saved, and missing in old backups means false', () {
      final a = Account(id: 'x', name: 'X', type: 'Cash', isDefault: true);
      expect(Account.fromMap(a.toMap()).isDefault, isTrue);
      final old = a.toMap()..remove('is_default');
      expect(Account.fromMap(old).isDefault, isFalse);
    });
  });
}
