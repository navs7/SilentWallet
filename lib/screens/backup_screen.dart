import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/crypto.dart';
import '../core/repo.dart';
import '../services/backup.dart';
import '../services/lock.dart';
import '../services/notifications.dart';
import '../services/settings.dart';
import '../util.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String _status = '';

  Future<void> _run(String status, Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _status = status;
    });
    try {
      await job();
    } on BadBackupException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterBackup() async {
    final s = context.read<Settings>();
    await s.markBackedUp();
    if (s.weeklyReminder) await Notifier.scheduleBackupReminder();
  }

  Future<void> _export({required bool share}) async {
    final pw = await askPassword(context,
        title: 'Set a backup password',
        hint: 'This password encrypts the file. There is no way to recover it — write it down.',
        confirmField: true);
    if (pw == null || !mounted) return;
    final repo = context.read<Repo>();
    final lock = context.read<LockController>();
    await _run('Encrypting backup…', () async {
      final bytes = await BackupService.build(repo, pw);
      final name = BackupService.backupFileName();
      if (share) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        final r = await lock.suspendLock(() =>
            SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Silent Wallet backup')));
        try {
          await f.delete();
        } catch (_) {}
        if (r.status == ShareResultStatus.dismissed) return;
      } else {
        final uri = await lock.suspendLock(() => FilePicker.saveFile(
              fileName: name,
              bytes: bytes,
              dialogTitle: 'Save backup',
            ));
        if (uri == null) return;
      }
      await _afterBackup();
      if (mounted) toast(context, 'Backup saved. Keep the file and the password safe.');
    });
  }

  Future<void> _exportCsv() async {
    if (!await confirm(context, 'Export CSV?',
        'The CSV file is NOT encrypted. Anyone who gets the file can read your transactions.',
        ok: 'Export')) {
      return;
    }
    if (!mounted) return;
    final repo = context.read<Repo>();
    final lock = context.read<LockController>();
    await _run('Preparing CSV…', () async {
      final text = await BackupService.csv(repo);
      final name = 'silentwallet-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      await lock.suspendLock(() => FilePicker.saveFile(
            fileName: name,
            bytes: Uint8List.fromList(utf8.encode(text)),
            mimeType: 'text/csv',
            dialogTitle: 'Save CSV',
          ));
    });
  }

  Future<void> _import() async {
    final lock = context.read<LockController>();
    final repo = context.read<Repo>();
    final picked = await lock.suspendLock(() => FilePicker.pickFile(dialogTitle: 'Choose backup file'));
    if (picked == null || !mounted) return;
    final pw = await askPassword(context, title: 'Backup password');
    if (pw == null || !mounted) return;
    if (!await confirm(context, 'Replace all data?',
        'Restoring will ERASE everything currently in the app and replace it with the backup.',
        ok: 'Restore')) {
      return;
    }
    await _run('Decrypting and restoring…', () async {
      if (picked.path == null) throw BadBackupException('Could not read that file.');
      final bytes = await File(picked.path!).readAsBytes();
      await BackupService.restore(repo, bytes, pw);
      if (picked.path != null) {
        try {
          await File(picked.path!).delete();
        } catch (_) {}
      }
      if (mounted) toast(context, 'Backup restored.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final last = s.lastBackup;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(last == null
                  ? 'You have never backed up'
                  : 'Last backup: ${DateFormat('d MMM yyyy, h:mm a').format(last)}'),
              subtitle: const Text(
                  'Silent Wallet never uploads anything. If you lose or reset this phone, only a backup file can bring your data back.'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _export(share: false),
            icon: const Icon(Icons.save_alt),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Save encrypted backup to device')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _export(share: true),
            icon: const Icon(Icons.share),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Share encrypted backup…')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.restore),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Restore from backup file')),
          ),
          const Divider(height: 40),
          SwitchListTile(
            value: s.weeklyReminder,
            title: const Text('Weekly backup reminder'),
            subtitle: const Text('Local notification, repeats every 7 days'),
            onChanged: (v) async {
              await s.setWeeklyReminder(v);
              if (v) {
                await Notifier.requestPermission();
                await Notifier.scheduleBackupReminder();
              } else {
                await Notifier.cancelBackupReminder();
              }
            },
          ),
          const Divider(height: 40),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export CSV (unencrypted)'),
            subtitle: const Text('For spreadsheets. Not a backup — receipts are not included.'),
            onTap: _busy ? null : _exportCsv,
          ),
        ]),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_status),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
