import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/lock.dart';
import '../services/notifications.dart';
import '../services/settings.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool lock = true;
  bool reminder = true;
  bool busy = false;

  Future<void> _start() async {
    setState(() => busy = true);
    final settings = context.read<Settings>();
    final lockCtl = context.read<LockController>();
    var enableLock = lock;
    if (enableLock && !await lockCtl.deviceSupported()) {
      enableLock = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set a screen lock (PIN / pattern / fingerprint) in Android settings to use app lock.',
            ),
          ),
        );
      }
    }
    await settings.setLock(enableLock);
    await settings.setWeeklyReminder(reminder);
    if (reminder) {
      await Notifier.requestPermission();
      await Notifier.scheduleBackupReminder();
    }
    await settings.setOnboarded();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(Icons.shield_moon_outlined, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Silent Wallet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Your expenses stay on this phone. Always.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            const _Point(
              Icons.wifi_off,
              'No internet access',
              'The app has no network permission. Nothing is ever uploaded.',
            ),
            const _Point(
              Icons.enhanced_encryption_outlined,
              'Encrypted storage',
              'Data and receipt photos are encrypted with a key kept in the phone\'s secure hardware.',
            ),
            const _Point(
              Icons.save_alt,
              'You own the backups',
              'There is no cloud. Export an encrypted backup file regularly — if you lose the phone without one, the data is gone.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: lock,
              onChanged: (v) => setState(() => lock = v),
              title: const Text('Lock app with fingerprint / PIN'),
              subtitle: const Text('Uses your phone\'s own screen lock'),
            ),
            SwitchListTile(
              value: reminder,
              onChanged: (v) => setState(() => reminder = v),
              title: const Text('Weekly backup reminder'),
              subtitle: const Text('A local notification, never from a server'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _start,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const _Point(this.icon, this.title, this.body);
  @override
  Widget build(BuildContext context) =>
      ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(body));
}
