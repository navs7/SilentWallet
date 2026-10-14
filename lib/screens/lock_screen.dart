import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    if (!mounted) return;
    await context.read<LockController>().unlock();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text('Silent Wallet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Locked'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _try,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ]),
        ),
      ),
    );
  }
}
