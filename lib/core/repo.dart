import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'crypto.dart';
import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class Repo extends ChangeNotifier {
  late final Database db;
  late final List<int> _fileKey;
  late final Directory _receiptDir;

  List<Account> accounts = [];
  List<Category> categories = [];
  List<Recurring> recurring = [];
  bool hasData = false; // any transaction ever recorded
  int version = 0; // bumped on every change so screens can refresh

  @override
  void notifyListeners() {
    version++;
    super.notifyListeners();
  }

  static Future<Repo> open() async {
    final r = Repo();
    final dir = await getApplicationDocumentsDirectory();
    r._receiptDir = Directory(p.join(dir.path, 'receipts'));
    await r._receiptDir.create(recursive: true);
    r._fileKey = await KeyStore.fileKey();
    final dbKey = await KeyStore.dbKey();
    r.db = await openDatabase(
      p.join(dir.path, 'silentwallet.db'),
      password: dbKey, // SQLCipher: whole database file is AES-256 encrypted
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE accounts(
          id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL,
          opening_balance INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE categories(
          id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL,
          color INTEGER NOT NULL, kind TEXT NOT NULL, is_custom INTEGER NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE transactions(
          id TEXT PRIMARY KEY, type TEXT NOT NULL, amount INTEGER NOT NULL,
          account_id TEXT NOT NULL, to_account_id TEXT, category_id TEXT,
          note TEXT, date INTEGER NOT NULL, receipt TEXT, recurring_id TEXT)''');
        await db.execute('CREATE INDEX idx_tx_date ON transactions(date)');
        await db.execute('''CREATE TABLE recurring(
          id TEXT PRIMARY KEY, title TEXT NOT NULL, type TEXT NOT NULL,
          amount INTEGER NOT NULL, account_id TEXT NOT NULL, category_id TEXT,
          frequency TEXT NOT NULL, next_due INTEGER NOT NULL,
          anchor_day INTEGER NOT NULL, end_date INTEGER, active INTEGER NOT NULL DEFAULT 1)''');
        await _seed(db);
      },
    );
    await r.reload();
    return r;
  }

  static Future<void> _seed(Database db) async {
    final b = db.batch();
    b.insert('accounts', Account(id: newId(), name: 'Cash', type: 'Cash').toMap());
    const exp = [
      ('Food & Dining', 'restaurant'), ('Groceries', 'cart'), ('Shopping', 'bag'),
      ('Transport', 'transport'), ('Fuel', 'fuel'), ('Rent & Home', 'home'),
      ('Bills & Utilities', 'bolt'), ('Mobile & Internet', 'phone'),
      ('Health', 'health'), ('Education', 'school'), ('Entertainment', 'movie'),
      ('Travel', 'flight'), ('Gifts', 'gift'), ('Other', 'other'),
    ];
    for (var i = 0; i < exp.length; i++) {
      b.insert('categories', Category(
        id: newId(), name: exp[i].$1, icon: exp[i].$2,
        color: categoryColors[i % categoryColors.length], kind: TxType.expense,
      ).toMap());
    }
    const inc = [('Salary', 'salary'), ('Business', 'business'),
      ('Interest', 'savings'), ('Gifts', 'gift'), ('Other', 'other')];
    for (var i = 0; i < inc.length; i++) {
      b.insert('categories', Category(
        id: newId(), name: inc[i].$1, icon: inc[i].$2,
        color: categoryColors[(i * 2 + 7) % categoryColors.length], kind: TxType.income,
      ).toMap());
    }
    await b.commit(noResult: true);
  }

  Future<void> reload() async {
    accounts = (await db.query('accounts', orderBy: 'name COLLATE NOCASE'))
        .map(Account.fromMap).toList();
    categories = (await db.query('categories', orderBy: 'name COLLATE NOCASE'))
        .map(Category.fromMap).toList();
    recurring = (await db.query('recurring', orderBy: 'next_due'))
        .map(Recurring.fromMap).toList();
    hasData = (Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM transactions')) ??
            0) >
        0;
    notifyListeners();
  }

  Account? account(String? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? category(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---------- Accounts ----------
  Future<void> saveAccount(Account a) async {
    await db.insert('accounts', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await reload();
  }

  Future<bool> deleteAccount(String id) async {
    final used = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE account_id=? OR to_account_id=?',
        [id, id])) ?? 0;
    final rec = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM recurring WHERE account_id=?', [id])) ?? 0;
    if (used > 0 || rec > 0) return false;
    await db.delete('accounts', where: 'id=?', whereArgs: [id]);
    await reload();
    return true;
  }

  // ---------- Categories ----------
  Future<void> saveCategory(Category c) async {
    await db.insert('categories', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await reload();
  }

  Future<bool> deleteCategory(String id) async {
    final used = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM transactions WHERE category_id=?', [id])) ?? 0;
    final rec = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM recurring WHERE category_id=?', [id])) ?? 0;
    if (used > 0 || rec > 0) return false;
    await db.delete('categories', where: 'id=?', whereArgs: [id]);
    await reload();
    return true;
  }

  // ---------- Transactions ----------
  Future<void> saveTx(Tx t) async {
    await db.insert('transactions', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    hasData = true;
    notifyListeners();
  }

  Future<void> deleteTx(Tx t) async {
    await db.delete('transactions', where: 'id=?', whereArgs: [t.id]);
    if (t.receipt != null) await deleteReceipt(t.receipt!);
    notifyListeners();
  }

  Future<List<Tx>> txBetween(DateTime from, DateTime to,
      {String? accountId, String? categoryId, String? search}) async {
    final where = <String>['date >= ? AND date < ?'];
    final args = <Object?>[from.millisecondsSinceEpoch, to.millisecondsSinceEpoch];
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args..add(accountId)..add(accountId);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('note LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows = await db.query('transactions',
        where: where.join(' AND '), whereArgs: args, orderBy: 'date DESC, rowid DESC');
    return rows.map(Tx.fromMap).toList();
  }

  Future<List<Tx>> allTx() async =>
      (await db.query('transactions', orderBy: 'date DESC')).map(Tx.fromMap).toList();

  /// Balance per account (paise) = opening + income - expense +/- transfers.
  Future<Map<String, int>> balances() async {
    final bal = {for (final a in accounts) a.id: a.openingBalance};
    for (final r in await db.query('transactions',
        columns: ['type', 'amount', 'account_id', 'to_account_id'])) {
      final amt = (r['amount'] as num).toInt();
      final from = r['account_id'] as String;
      final to = r['to_account_id'] as String?;
      switch (r['type']) {
        case 'income':
          bal[from] = (bal[from] ?? 0) + amt;
        case 'expense':
          bal[from] = (bal[from] ?? 0) - amt;
        case 'transfer':
          bal[from] = (bal[from] ?? 0) - amt;
          if (to != null) bal[to] = (bal[to] ?? 0) + amt;
      }
    }
    return bal;
  }

  // ---------- Recurring ----------
  Future<void> saveRecurring(Recurring r) async {
    await db.insert('recurring', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await reload();
  }

  Future<void> deleteRecurring(String id) async {
    await db.delete('recurring', where: 'id=?', whereArgs: [id]);
    await reload();
  }

  /// Creates every missed occurrence up to today. Returns how many were added.
  Future<int> processRecurring() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var created = 0;
    for (final r in recurring.where((r) => r.active)) {
      var changed = false;
      var guard = 0;
      while (!r.nextDue.isAfter(today) && guard++ < 1000) {
        if (r.endDate != null && r.nextDue.isAfter(r.endDate!)) {
          r.active = false;
          changed = true;
          break;
        }
        await db.insert('transactions', Tx(
          id: newId(), type: r.type, amount: r.amount, accountId: r.accountId,
          categoryId: r.categoryId, note: r.title, date: r.nextDue, recurringId: r.id,
        ).toMap());
        created++;
        r.nextDue = nextOccurrence(r.nextDue, r.frequency, anchorDay: r.anchorDay);
        changed = true;
      }
      if (changed) {
        await db.insert('recurring', r.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (created > 0) await reload();
    return created;
  }

  // ---------- Receipts (AES-256-GCM encrypted files) ----------
  Future<String> saveReceipt(Uint8List jpg) async {
    final name = '${newId()}.enc';
    await File(p.join(_receiptDir.path, name))
        .writeAsBytes(await encryptBytes(jpg, _fileKey), flush: true);
    return name;
  }

  Future<Uint8List?> readReceipt(String name) async {
    final f = File(p.join(_receiptDir.path, name));
    if (!await f.exists()) return null;
    return decryptBytes(await f.readAsBytes(), _fileKey);
  }

  Future<void> deleteReceipt(String name) async {
    final f = File(p.join(_receiptDir.path, name));
    if (await f.exists()) await f.delete();
  }

  // ---------- Backup support ----------
  Future<Map<String, Object?>> dumpAll() async => {
        'accounts': await db.query('accounts'),
        'categories': await db.query('categories'),
        'transactions': await db.query('transactions'),
        'recurring': await db.query('recurring'),
      };

  Future<void> restoreAll(Map<String, dynamic> data) async {
    await db.transaction((txn) async {
      for (final t in ['transactions', 'recurring', 'categories', 'accounts']) {
        await txn.delete(t);
      }
      for (final t in ['accounts', 'categories', 'transactions', 'recurring']) {
        for (final row in (data[t] as List)) {
          await txn.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
    });
    // Remove receipt files not referenced any more.
    final keep = (await db.query('transactions', columns: ['receipt']))
        .map((r) => r['receipt']).whereType<String>().toSet();
    for (final f in _receiptDir.listSync().whereType<File>()) {
      if (!keep.contains(p.basename(f.path))) await f.delete();
    }
    await reload();
  }

  Future<void> writeReceiptRaw(String name, Uint8List jpg) async {
    await File(p.join(_receiptDir.path, name))
        .writeAsBytes(await encryptBytes(jpg, _fileKey), flush: true);
  }
}
