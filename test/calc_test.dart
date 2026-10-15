import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/core/calc.dart';

void main() {
  group('evaluateExpression', () {
    test('plain numbers', () {
      expect(evaluateExpression('150'), 150);
      expect(evaluateExpression('12.5'), 12.5);
      expect(evaluateExpression('0.05'), 0.05);
    });

    test('addition and subtraction', () {
      expect(evaluateExpression('120+35.5'), 155.5);
      expect(evaluateExpression('500-120-30'), 350);
      expect(evaluateExpression('10-20'), -10);
    });

    test('multiplication and division come before + and -', () {
      expect(evaluateExpression('2+3×4'), 14);
      expect(evaluateExpression('20-10÷2'), 15);
      expect(evaluateExpression('100÷4×3'), 75); // left to right
      expect(evaluateExpression('2×3+4×5'), 26);
    });

    test('incomplete or invalid text gives null', () {
      expect(evaluateExpression(''), isNull);
      expect(evaluateExpression('12+'), isNull);
      expect(evaluateExpression('+5'), isNull);
      expect(evaluateExpression('5×'), isNull);
      expect(evaluateExpression('.'), isNull);
      expect(evaluateExpression('abc'), isNull);
      expect(evaluateExpression('5÷0'), isNull);
      expect(evaluateExpression('5÷0+2'), isNull);
    });

    test('a trailing dot is allowed', () {
      expect(evaluateExpression('5.'), 5);
      expect(evaluateExpression('5.+2'), 7);
    });
  });

  group('formatAmount', () {
    test('drops useless trailing zeros and rounds to paise', () {
      expect(formatAmount(100), '100');
      expect(formatAmount(100.5), '100.5');
      expect(formatAmount(100.25), '100.25');
      expect(formatAmount(0.1 + 0.2), '0.3');
      expect(formatAmount(10 / 3), '3.33');
      expect(formatAmount(1000000), '1000000');
    });
  });

  group('AmountEntry keys', () {
    AmountEntry type(String keys) {
      final e = AmountEntry();
      for (final k in keys.split('')) {
        e.press(k);
      }
      return e;
    }

    test('digits and a decimal point', () {
      expect(type('1234.5').text, '1234.5');
      expect(type('.5').text, '0.5'); // leading dot becomes 0.
    });

    test('at most two decimals and nine integer digits', () {
      expect(type('1.234').text, '1.23');
      expect(type('1234567890').text, '123456789');
    });

    test('only one decimal point per number', () {
      expect(type('1..2').text, '1.2');
      expect(type('1.5+2.5.5').text, '1.5+2.55');
    });

    test('no leading zeros', () {
      expect(type('007').text, '7');
      expect(type('0').text, '0');
      expect(type('0.5').text, '0.5');
      expect(type('5+05').text, '5+5');
    });

    test('operators are replaced, not stacked; none at the start', () {
      expect(type('+5').text, '5');
      expect(type('5+-').text, '5-');
      expect(type('5×÷3').text, '5÷3');
    });

    test('an operator after a trailing dot drops the dot', () {
      expect(type('5.+').text, '5+');
    });

    test('backspace and clear', () {
      final e = type('12+5');
      e.press('⌫');
      expect(e.text, '12+');
      e.press('⌫');
      e.press('⌫');
      expect(e.text, '1');
      e.press('C');
      expect(e.text, '');
      e.press('⌫'); // nothing to delete
      expect(e.text, '');
    });

    test('length is capped', () {
      final e = AmountEntry();
      for (var i = 0; i < 40; i++) {
        e.press('1');
        e.press('+');
      }
      expect(e.text.length, lessThanOrEqualTo(AmountEntry.maxLength));
    });
  });

  group('AmountEntry value', () {
    test('hasOperator', () {
      expect(AmountEntry('12').hasOperator, isFalse);
      expect(AmountEntry('12+3').hasOperator, isTrue);
      expect(AmountEntry('12.5').hasOperator, isFalse);
    });

    test('paise for a plain number or a calculation', () {
      expect(AmountEntry('250.5').paise, 25050);
      expect(AmountEntry('120+35.5').paise, 15550);
      expect(AmountEntry('19.99').paise, 1999);
      expect(AmountEntry('0.1+0.2').paise, 30);
    });

    test('paise is null for zero, negative or incomplete input', () {
      expect(AmountEntry('').paise, isNull);
      expect(AmountEntry('0').paise, isNull);
      expect(AmountEntry('5-10').paise, isNull);
      expect(AmountEntry('5+').paise, isNull);
      expect(AmountEntry('5÷0').paise, isNull);
    });

    test('equals() replaces a calculation with its result', () {
      final e = AmountEntry('120+35.5×2');
      expect(e.equals(), isTrue);
      expect(e.text, '191');
      expect(e.hasOperator, isFalse);
    });

    test('equals() leaves invalid or plain text alone', () {
      final a = AmountEntry('5-10');
      expect(a.equals(), isFalse);
      expect(a.text, '5-10');
      final b = AmountEntry('12');
      expect(b.equals(), isFalse);
      expect(b.text, '12');
      final c = AmountEntry('5+');
      expect(c.equals(), isFalse);
    });
  });
}
