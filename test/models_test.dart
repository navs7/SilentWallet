import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/core/models.dart';

void main() {
  group('nextOccurrence', () {
    test('daily and weekly', () {
      expect(nextOccurrence(DateTime(2026, 1, 31), Frequency.daily), DateTime(2026, 2, 1));
      expect(nextOccurrence(DateTime(2026, 12, 28), Frequency.weekly), DateTime(2027, 1, 4));
    });

    test('monthly keeps the same day', () {
      expect(nextOccurrence(DateTime(2026, 5, 15), Frequency.monthly), DateTime(2026, 6, 15));
    });

    test('monthly clamps to a short month', () {
      expect(nextOccurrence(DateTime(2026, 1, 31), Frequency.monthly, anchorDay: 31),
          DateTime(2026, 2, 28));
      expect(nextOccurrence(DateTime(2028, 1, 31), Frequency.monthly, anchorDay: 31),
          DateTime(2028, 2, 29)); // leap year
    });

    test('monthly returns to the anchor day after a short month', () {
      final feb = nextOccurrence(DateTime(2026, 1, 31), Frequency.monthly, anchorDay: 31);
      final mar = nextOccurrence(feb, Frequency.monthly, anchorDay: 31);
      expect(mar, DateTime(2026, 3, 31));
      final apr = nextOccurrence(mar, Frequency.monthly, anchorDay: 31);
      expect(apr, DateTime(2026, 4, 30));
    });

    test('monthly rolls over the year', () {
      expect(nextOccurrence(DateTime(2026, 12, 10), Frequency.monthly), DateTime(2027, 1, 10));
    });

    test('yearly handles 29 February', () {
      expect(nextOccurrence(DateTime(2028, 2, 29), Frequency.yearly), DateTime(2029, 2, 28));
      expect(nextOccurrence(DateTime(2026, 7, 4), Frequency.yearly), DateTime(2027, 7, 4));
    });

    test('catching up a year of months produces 12 distinct dates', () {
      var d = DateTime(2026, 1, 31);
      final seen = <DateTime>{};
      for (var i = 0; i < 12; i++) {
        d = nextOccurrence(d, Frequency.monthly, anchorDay: 31);
        seen.add(d);
      }
      expect(seen.length, 12);
      expect(d, DateTime(2027, 1, 31));
    });
  });

  group('serialization round-trips', () {
    test('Account', () {
      final a = Account(id: 'a1', name: 'HDFC', type: 'Bank', openingBalance: 123456, archived: true);
      final b = Account.fromMap(a.toMap());
      expect(b.id, 'a1');
      expect(b.name, 'HDFC');
      expect(b.type, 'Bank');
      expect(b.openingBalance, 123456);
      expect(b.archived, isTrue);
    });

    test('Category', () {
      final c = Category(
          id: 'c1', name: 'Snacks', icon: 'restaurant', color: 0xFFE57373,
          kind: TxType.expense, isCustom: true);
      final d = Category.fromMap(c.toMap());
      expect(d.name, 'Snacks');
      expect(d.kind, TxType.expense);
      expect(d.color, 0xFFE57373);
      expect(d.isCustom, isTrue);
      expect(d.iconData, categoryIcons['restaurant']);
    });

    test('unknown category icon falls back safely', () {
      final c = Category(id: 'c', name: 'x', icon: 'nope', color: 0, kind: TxType.income);
      expect(c.iconData, categoryIcons['other']);
    });

    test('Tx keeps every field, including a transfer and receipt', () {
      final t = Tx(
        id: 't1', type: TxType.transfer, amount: 99900, accountId: 'a1',
        toAccountId: 'a2', note: 'rent, march', date: DateTime(2026, 3, 1, 9, 30),
        receipt: 'r.enc', recurringId: 'rr1',
      );
      final u = Tx.fromMap(t.toMap());
      expect(u.type, TxType.transfer);
      expect(u.amount, 99900);
      expect(u.toAccountId, 'a2');
      expect(u.categoryId, isNull);
      expect(u.note, 'rent, march');
      expect(u.date, DateTime(2026, 3, 1, 9, 30));
      expect(u.receipt, 'r.enc');
      expect(u.recurringId, 'rr1');
    });

    test('Tx tolerates a null note from the database', () {
      final m = Tx(id: 't', type: TxType.expense, amount: 1, accountId: 'a', date: DateTime(2026))
          .toMap()
        ..['note'] = null;
      expect(Tx.fromMap(m).note, '');
    });

    test('Recurring with and without an end date', () {
      final r = Recurring(
        id: 'r1', title: 'Rent', type: TxType.expense, amount: 1500000,
        accountId: 'a1', frequency: Frequency.monthly,
        nextDue: DateTime(2026, 4, 1), anchorDay: 1,
      );
      final a = Recurring.fromMap(r.toMap());
      expect(a.endDate, isNull);
      expect(a.frequency, Frequency.monthly);
      expect(a.anchorDay, 1);
      expect(a.active, isTrue);

      r.endDate = DateTime(2027, 1, 1);
      r.active = false;
      final b = Recurring.fromMap(r.toMap());
      expect(b.endDate, DateTime(2027, 1, 1));
      expect(b.active, isFalse);
    });
  });

  test('default palettes are non-empty', () {
    expect(categoryColors, isNotEmpty);
    expect(categoryIcons.containsKey('other'), isTrue);
    expect(accountTypes.containsKey('Cash'), isTrue);
  });
}
