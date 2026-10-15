import 'package:flutter/material.dart';

/// In-app amount keypad: digits, a decimal point, backspace, minus, a
/// calculator key (adds a row of ÷ × + =) and a Done key. The header has a
/// globe (use the phone's own keyboard instead) and a close button.
///
/// Key logic lives in `AmountEntry`; this widget only reports key presses.
class AmountPad extends StatelessWidget {
  final bool calculator;
  final double rowHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onDone;
  final VoidCallback onEquals;
  final VoidCallback onClose;
  final VoidCallback onPhoneKeyboard;
  final VoidCallback onToggleCalculator;

  const AmountPad({
    super.key,
    required this.calculator,
    required this.rowHeight,
    required this.onKey,
    required this.onDone,
    required this.onEquals,
    required this.onClose,
    required this.onPhoneKeyboard,
    required this.onToggleCalculator,
  });

  static const _bg = Color(0xFF2B2C30);
  static const _line = Color(0xFF3C3D42);
  static const _header = Color(0xFF808185);
  static const _active = Color(0xFF3F4046);
  static const _coral = Color(0xFFFF6459);
  static const _label = TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w400,
  );

  Widget _cell({
    required String id,
    Widget? child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Color color = _bg,
  }) {
    return Expanded(
      child: Material(
        color: color,
        child: InkWell(
          key: Key('pad-$id'),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: _line, width: 0.5),
                right: BorderSide(color: _line, width: 0.5),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _text(String id, String shown, {String? sends}) => _cell(
    id: id,
    onTap: () => onKey(sends ?? shown),
    child: Text(shown, style: _label),
  );

  Widget _row(List<Widget> cells) => SizedBox(
    height: rowHeight,
    child: Row(children: cells),
  );

  Widget _headerBar() {
    Widget action(String id, IconData icon, VoidCallback onTap, String tip) =>
        InkWell(
          key: Key('pad-$id'),
          onTap: onTap,
          child: Tooltip(
            message: tip,
            child: SizedBox(
              width: 44,
              height: 32,
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          ),
        );
    return Container(
      height: 32,
      color: _header,
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: [
          const Text(
            'Amount',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const Spacer(),
          action(
            'globe',
            Icons.language,
            onPhoneKeyboard,
            'Use phone keyboard',
          ),
          action('close', Icons.close, onClose, 'Close keypad'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerBar(),
          if (calculator)
            _row([
              _text('div', '÷'),
              _text('mul', '×'),
              _text('plus', '+'),
              _cell(
                id: 'eq',
                onTap: onEquals,
                child: const Text('=', style: _label),
              ),
            ]),
          _row([
            _text('1', '1'),
            _text('2', '2'),
            _text('3', '3'),
            _cell(
              id: 'back',
              onTap: () => onKey('⌫'),
              onLongPress: () => onKey('C'),
              child: const Icon(Icons.backspace_outlined, color: Colors.white),
            ),
          ]),
          _row([
            _text('4', '4'),
            _text('5', '5'),
            _text('6', '6'),
            _text('minus', '−', sends: '-'),
          ]),
          _row([
            _text('7', '7'),
            _text('8', '8'),
            _text('9', '9'),
            _cell(
              id: 'calc',
              onTap: onToggleCalculator,
              color: calculator ? _active : _bg,
              child: const Icon(Icons.calculate_outlined, color: Colors.white),
            ),
          ]),
          _row([
            _cell(id: 'blank'),
            _text('0', '0'),
            _text('dot', '.'),
            _cell(
              id: 'done',
              onTap: onDone,
              color: _coral,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
