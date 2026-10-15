import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a root page. A back gesture first lets the page undo its own state
/// ([onBack] returns true when it handled it, e.g. closing a search box or
/// returning to the first tab). Only at the top level does it ask for a second
/// press within [window] before exiting the app.
class BackGuard extends StatefulWidget {
  final Widget child;
  final bool Function() onBack;
  final VoidCallback? onExit;
  final Duration window;
  const BackGuard({
    super.key,
    required this.child,
    required this.onBack,
    this.onExit,
    this.window = const Duration(seconds: 2),
  });

  @override
  State<BackGuard> createState() => _BackGuardState();
}

class _BackGuardState extends State<BackGuard> {
  DateTime? _lastBack;

  void _handle(bool didPop, Object? result) {
    if (didPop) return;
    if (widget.onBack()) {
      _lastBack = null;
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) <= widget.window) {
      (widget.onExit ?? SystemNavigator.pop)();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Press back again to exit'),
          duration: widget.window,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: _handle,
    child: widget.child,
  );
}
