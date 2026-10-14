import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/util.dart';

void main() {
  group('parseAmount', () {
    test('converts rupees to paise', () {
      expect(parseAmount('150'), 15000);
      expect(parseAmount('150.5'), 15050);
      expect(parseAmount('0.01'), 1);
    });

    test('ignores thousands separators and spaces', () {
      expect(parseAmount('1,234.50'), 123450);
      expect(parseAmount('  99 '), 9900);
    });

    test('avoids floating point drift', () {
      expect(parseAmount('19.99'), 1999);
      expect(parseAmount('0.29'), 29);
      expect(parseAmount('1.005'), anyOf(100, 101)); // rounds to nearest paisa
    });

    test('rejects invalid, zero and negative values', () {
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
      expect(parseAmount('0'), isNull);
      expect(parseAmount('-5'), isNull);
      expect(parseAmount('1e12'), isNull);
    });
  });

  group('money', () {
    test('formats with rupee sign and Indian grouping', () {
      expect(money(12345600), '₹1,23,456.00');
      expect(money(50), '₹0.50');
    });

    test('compact drops .00 only for whole rupees', () {
      expect(money(10000, compact: true), '₹100');
      expect(money(10050, compact: true), '₹100.50');
    });

    test('formats negatives', () {
      expect(money(-2500), contains('25.00'));
      expect(money(-2500), contains('-'));
    });
  });

  group('dates', () {
    test('dayOf strips the time', () {
      expect(dayOf(DateTime(2026, 3, 5, 23, 59)), DateTime(2026, 3, 5));
    });

    test('dayLabel names today and yesterday', () {
      final now = DateTime.now();
      expect(dayLabel(now), 'Today');
      expect(dayLabel(now.subtract(const Duration(days: 1))), 'Yesterday');
      expect(dayLabel(DateTime(2020, 1, 15)), 'Wed, 15 Jan 2020');
    });

    test('monthRange covers exactly one month', () {
      final r = monthRange(DateTime(2026, 2, 17));
      expect(r.from, DateTime(2026, 2, 1));
      expect(r.to, DateTime(2026, 3, 1));
      expect(r.label, 'February 2026');
    });

    test('monthRange rolls over the year', () {
      final r = monthRange(DateTime(2026, 12, 3));
      expect(r.to, DateTime(2027, 1, 1));
    });
  });
}
