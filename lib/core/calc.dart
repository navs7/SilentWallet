/// Evaluates an amount expression such as `120+35.5×2-6÷3` with normal
/// operator precedence (× and ÷ before + and -). Returns null when the text is
/// not a complete valid expression (empty, trailing operator, divide by zero).
double? evaluateExpression(String input) {
  final tokens = <String>[];
  final cur = StringBuffer();
  for (final ch in input.split('')) {
    if ('0123456789.'.contains(ch)) {
      cur.write(ch);
    } else if ('+-×÷'.contains(ch)) {
      if (cur.isEmpty) return null;
      tokens
        ..add(cur.toString())
        ..add(ch);
      cur.clear();
    } else {
      return null;
    }
  }
  if (cur.isEmpty) return null; // empty, or ends with an operator
  tokens.add(cur.toString());

  double? number(String t) {
    final s = t.endsWith('.') ? t.substring(0, t.length - 1) : t;
    return s.isEmpty ? null : double.tryParse(s);
  }

  var acc = number(tokens[0]);
  if (acc == null) return null;
  final terms = <double>[];
  final signs = <String>[];
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i];
    final n = number(tokens[i + 1]);
    if (n == null) return null;
    if (op == '×') {
      acc = acc! * n;
    } else if (op == '÷') {
      if (n == 0) return null;
      acc = acc! / n;
    } else {
      terms.add(acc!);
      signs.add(op);
      acc = n;
    }
  }
  terms.add(acc!);
  var result = terms[0];
  for (var i = 0; i < signs.length; i++) {
    result = signs[i] == '+' ? result + terms[i + 1] : result - terms[i + 1];
  }
  return result.isFinite ? result : null;
}

/// Rounds to paise and drops useless trailing zeros: 100.00 -> "100",
/// 100.50 -> "100.5".
String formatAmount(double v) {
  final s = ((v * 100).round() / 100).toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// The text typed on the amount keypad, with the rules for each key.
/// Keys: `0`-`9`, `.`, `+`, `-`, `×`, `÷`, `⌫` (backspace), `C` (clear).
class AmountEntry {
  String text;
  AmountEntry([this.text = '']);

  static const _operators = '+-×÷';
  static const maxLength = 30;
  static const maxIntegerDigits = 9;
  static const maxDecimals = 2;

  bool get hasOperator => text.split('').any(_operators.contains);

  /// Value of the expression, rounded to paise; null if incomplete/invalid.
  double? get value {
    final v = evaluateExpression(text);
    return v == null ? null : (v * 100).round() / 100;
  }

  /// Amount in paise; null unless the expression is valid and above zero.
  int? get paise {
    final v = value;
    return (v == null || v <= 0) ? null : (v * 100).round();
  }

  /// Replaces a pending calculation with its result (valid and above zero).
  bool equals() {
    if (!hasOperator) return false;
    final v = value;
    if (v == null || v <= 0) return false;
    text = formatAmount(v);
    return true;
  }

  String get _currentNumber {
    var i = text.length;
    while (i > 0 && !_operators.contains(text[i - 1])) {
      i--;
    }
    return text.substring(i);
  }

  void press(String key) {
    switch (key) {
      case '⌫':
        if (text.isNotEmpty) text = text.substring(0, text.length - 1);
      case 'C':
        text = '';
      case '.':
        _dot();
      case '+' || '-' || '×' || '÷':
        _operator(key);
      default:
        if (key.length == 1 && '0123456789'.contains(key)) _digit(key);
    }
  }

  void _digit(String d) {
    if (text.length >= maxLength) return;
    final n = _currentNumber;
    final dot = n.indexOf('.');
    if (dot >= 0) {
      if (n.length - dot - 1 >= maxDecimals) return;
    } else if (n.length >= maxIntegerDigits && n != '0') {
      return;
    }
    // no leading zeros: "0" followed by 5 becomes "5"
    if (n == '0') {
      text = text.substring(0, text.length - 1) + d;
    } else {
      text += d;
    }
  }

  void _dot() {
    if (text.length >= maxLength) return;
    final n = _currentNumber;
    if (n.contains('.')) return;
    text += n.isEmpty ? '0.' : '.';
  }

  void _operator(String op) {
    if (text.isEmpty) return;
    if (_operators.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1) + op; // replace the operator
      return;
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    if (text.length >= maxLength) return;
    text += op;
  }
}
