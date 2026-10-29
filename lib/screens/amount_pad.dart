import 'package:flutter/material.dart';

/// In-app amount keypad in the app's own style: digits, a decimal point,
/// backspace, minus, a calculator key (adds a row of ÷ × + =) and a Done key.
/// The header has a close button.
///
/// Key logic lives in `AmountEntry`; this widget only reports key presses.
class AmountPad extends StatelessWidget {
  final bool calculator;
  final double rowHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onDone;
  final VoidCallback onEquals;
  final int gstPercent;
  final VoidCallback onGst;
  final VoidCallback onGstRate;
  final VoidCallback onClose;
  final VoidCallback onToggleCalculator;

  const AmountPad({
    super.key,
    required this.calculator,
    required this.rowHeight,
    required this.onKey,
    required this.onDone,
    required this.onEquals,
    this.gstPercent = 5,
    required this.onGst,
    required this.onGstRate,
    required this.onClose,
    required this.onToggleCalculator,
  });

  /// Total height of the pad for the given key height (header + rows + padding).
  static double heightFor(double rowHeight, bool calculator) =>
      34 + (calculator ? 5 : 4) * rowHeight + 6;

  Widget _key(
    BuildContext context, {
    required String id,
    Widget? child,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: onTap == null && child == null
              ? Colors.transparent
              : (color ?? cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('pad-$id'),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _text(
    BuildContext context,
    String id,
    String shown, {
    String? sends,
    bool operator = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _key(
      context,
      id: id,
      color: operator ? cs.secondaryContainer : null,
      onTap: () => onKey(sends ?? shown),
      child: Text(
        shown,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: operator ? cs.onSecondaryContainer : cs.onSurface,
        ),
      ),
    );
  }

  Widget _row(List<Widget> cells) => SizedBox(
    height: rowHeight,
    child: Row(children: cells),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                const SizedBox(width: 6),
                Text(
                  'Amount',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('pad-close'),
                  tooltip: 'Close keypad',
                  onPressed: onClose,
                  icon: const Icon(Icons.keyboard_hide_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          if (calculator)
            _row([
              _text(context, 'div', '÷', operator: true),
              _text(context, 'mul', '×', operator: true),
              _text(context, 'plus', '+', operator: true),
              _key(
                context,
                id: 'eq',
                color: cs.secondaryContainer,
                onTap: onEquals,
                child: Text(
                  '=',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ]),
          _row([
            _text(context, '1', '1'),
            _text(context, '2', '2'),
            _text(context, '3', '3'),
            _key(
              context,
              id: 'back',
              onTap: () => onKey('⌫'),
              onLongPress: () => onKey('C'),
              child: Icon(Icons.backspace_outlined, color: cs.onSurface),
            ),
          ]),
          _row([
            _text(context, '4', '4'),
            _text(context, '5', '5'),
            _text(context, '6', '6'),
            _text(context, 'minus', '−', sends: '-', operator: true),
          ]),
          _row([
            _text(context, '7', '7'),
            _text(context, '8', '8'),
            _text(context, '9', '9'),
            _key(
              context,
              id: 'calc',
              color: calculator ? cs.primaryContainer : cs.secondaryContainer,
              onTap: onToggleCalculator,
              child: Icon(
                Icons.calculate_outlined,
                color: calculator
                    ? cs.onPrimaryContainer
                    : cs.onSecondaryContainer,
              ),
            ),
          ]),
          _row([
            calculator
                ? _key(
                    context,
                    id: 'gst',
                    color: cs.secondaryContainer,
                    onTap: onGst,
                    onLongPress: onGstRate,
                    child: Text(
                      '$gstPercent% GST',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  )
                : _key(context, id: 'blank'),
            _text(context, '0', '0'),
            _text(context, 'dot', '.'),
            _key(
              context,
              id: 'done',
              color: cs.primary,
              onTap: onDone,
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
