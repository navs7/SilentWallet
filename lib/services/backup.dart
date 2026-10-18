import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../core/crypto.dart';
import '../core/repo.dart';

class BackupService {
  /// Builds a password-encrypted backup (data + decrypted receipts inside the
  /// encrypted container).
  static Future<Uint8List> build(Repo repo, String password) async {
    final data = await repo.dumpAll();
    final archive = Archive();
    final json = utf8.encode(jsonEncode({'version': 1, ...data}));
    archive.addFile(ArchiveFile('data.json', json.length, json));
    for (final row in data['transactions'] as List) {
      final name = (row as Map)['receipt'] as String?;
      if (name == null) continue;
      final bytes = await repo.readReceipt(name);
      if (bytes != null) {
        archive.addFile(ArchiveFile('receipts/$name', bytes.length, bytes));
      }
    }
    final zip = ZipEncoder().encode(archive);
    return encryptBackup(zip, password);
  }

  /// Replaces ALL current data with the backup's contents.
  static Future<void> restore(
    Repo repo,
    List<int> file,
    String password,
  ) async {
    final zip = await decryptBackup(file, password);
    final archive = ZipDecoder().decodeBytes(zip);
    final dataFile = archive.findFile('data.json');
    if (dataFile == null) {
      throw BadBackupException('Backup is missing its data.');
    }
    final data = jsonDecode(
      utf8.decode(dataFile.content as List<int>),
    ) as Map<String, dynamic>;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('receipts/')) continue;
      await repo.writeReceiptRaw(
        f.name.substring('receipts/'.length),
        Uint8List.fromList(f.content as List<int>),
      );
    }
    await repo.restoreAll(data);
  }

  static String backupFileName() =>
      'silentwallet-backup-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.swbak';

  /// Plain CSV of every transaction (for spreadsheets). NOT encrypted.
  static Future<String> csv(Repo repo) async {
    String esc(String s) =>
        (s.contains(',') || s.contains('"') || s.contains('\n'))
        ? '"${s.replaceAll('"', '""')}"'
        : s;
    final fmt = DateFormat('yyyy-MM-dd');
    final b = StringBuffer(
      'Date,Type,Amount (INR),Account,To Account,Category,Note,Comment\n',
    );
    for (final t in await repo.allTx()) {
      b.writeln(
        [
          fmt.format(t.date),
          t.type.name,
          (t.amount / 100).toStringAsFixed(2),
          esc(repo.account(t.accountId)?.name ?? ''),
          esc(repo.account(t.toAccountId)?.name ?? ''),
          esc(repo.category(t.categoryId)?.name ?? ''),
          esc(t.note),
          esc(t.comment),
        ].join(','),
      );
    }
    return b.toString();
  }
}
