import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/repo.dart';
import '../services/lock.dart';
import '../services/screen_guard.dart';
import '../services/settings.dart';
import '../util.dart';
import 'backup_screen.dart';
import 'categories_screen.dart';
import 'recurring_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext c, Widget w) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final repo = context.watch<Repo>();
    final lock = context.read<LockController>();
    final last = s.lastBackup;
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Text('More', style: Theme.of(context).textTheme.titleLarge),
        ),
        if (s.backupDue(repo.hasData))
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(
                last == null
                    ? 'No backup yet'
                    : 'Last backup ${DateFormat('d MMM').format(last)}',
              ),
              subtitle: const Text(
                'Your data exists only on this phone. Export an encrypted backup.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, const BackupScreen()),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.repeat),
          title: const Text('Recurring expenses'),
          onTap: () => _open(context, const RecurringScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.category),
          title: const Text('Categories'),
          onTap: () => _open(context, const CategoriesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.backup),
          title: const Text('Backup & restore'),
          subtitle: Text(
            last == null
                ? 'Never backed up'
                : 'Last backup ${DateFormat('d MMM yyyy').format(last)}',
          ),
          onTap: () => _open(context, const BackupScreen()),
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('App lock'),
          subtitle: const Text('Fingerprint / face / phone PIN'),
          value: s.lockEnabled,
          onChanged: (v) async {
            if (v) {
              if (!await lock.deviceSupported()) {
                if (context.mounted) {
                  toast(
                    context,
                    'Set a screen lock in Android settings first.',
                  );
                }
                return;
              }
              // Confirm the user can actually pass the check before enabling.
              if (!await lock.unlock()) return;
            }
            await s.setLock(v);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_outlined),
          title: const Text('Allow screenshots'),
          subtitle: const Text(
            'Off: screenshots and screen recording are blocked and the app is hidden in recent apps.',
          ),
          value: s.allowScreenshots,
          onChanged: (v) async {
            await s.setAllowScreenshots(v);
            await ScreenGuard.setSecure(!v);
          },
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: const Text('Theme'),
          trailing: DropdownButton<ThemeMode>(
            value: s.themeMode,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (m) => s.setTheme(m!),
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('Privacy'),
          subtitle: Text(
            'Silent Wallet has no internet permission, no analytics and no cloud. Data is encrypted on this phone and leaves only when you export a backup yourself.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Silent Wallet'),
          subtitle: Text('Version 1.0.9'),
        ),
      ],
    );
  }
}
