import 'package:flutter/material.dart';

enum TxType { expense, income, transfer }

enum Frequency { daily, weekly, monthly, yearly }

/// Size of a category's icon wherever it is shown next to a transaction or a
/// category tag, so the Add page and the transaction list match.
const double kCategoryIconSize = 14;

/// Smaller icon used in the transaction list rows.
const double kListIconSize = 12;

/// Icons a user can pick for a category. Stored by index-stable key.
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'cart': Icons.shopping_cart,
  'bag': Icons.shopping_bag,
  'transport': Icons.directions_bus,
  'car': Icons.directions_car,
  'fuel': Icons.local_gas_station,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'phone': Icons.smartphone,
  'health': Icons.local_hospital,
  'school': Icons.school,
  'movie': Icons.movie,
  'flight': Icons.flight,
  'gift': Icons.card_giftcard,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
  'salary': Icons.payments,
  'business': Icons.business_center,
  'savings': Icons.savings,
  'bank': Icons.account_balance,
  'other': Icons.category,
};

const categoryColors = <int>[
  0xFFE57373,
  0xFFF06292,
  0xFFBA68C8,
  0xFF9575CD,
  0xFF7986CB,
  0xFF64B5F6,
  0xFF4DD0E1,
  0xFF4DB6AC,
  0xFF81C784,
  0xFFAED581,
  0xFFFFD54F,
  0xFFFFB74D,
  0xFFA1887F,
  0xFF90A4AE,
];

const accountTypes = <String, IconData>{
  'Cash': Icons.account_balance_wallet,
  'Bank': Icons.account_balance,
  'Card': Icons.credit_card,
  'UPI / Wallet': Icons.phone_android,
  'Other': Icons.folder,
};

class Account {
  final String id;
  String name;
  String type;
  int openingBalance; // paise
  bool archived;
  bool isDefault; // pre-selected when adding a transaction
  Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalance = 0,
    this.archived = false,
    this.isDefault = false,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'opening_balance': openingBalance,
    'archived': archived ? 1 : 0,
    'is_default': isDefault ? 1 : 0,
  };

  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as String,
    name: m['name'] as String,
    type: m['type'] as String,
    openingBalance: (m['opening_balance'] as num).toInt(),
    archived: (m['archived'] as num) == 1,
    // Missing in backups made before the default-account feature.
    isDefault: ((m['is_default'] ?? 0) as num) == 1,
  );
}

/// The built-in "Other" category (or "Others") of the given kind, if present.
/// Transactions saved without a category are filed under it.
String? findOtherCategoryId(List<Category> categories, TxType kind) {
  for (final c in categories) {
    final n = c.name.trim().toLowerCase();
    if (c.kind == kind && (n == 'other' || n == 'others')) return c.id;
  }
  return null;
}

/// The account to pre-select for a new transaction: the one marked default
/// (if it is still active), otherwise the first active account.
String? defaultAccountId(List<Account> accounts) {
  final active = accounts.where((a) => !a.archived).toList();
  for (final a in active) {
    if (a.isDefault) return a.id;
  }
  return active.isEmpty ? null : active.first.id;
}

/// Accounts for a picker: the default first, the rest in their given order.
List<Account> accountsDefaultFirst(List<Account> accounts) => [
  ...accounts.where((a) => a.isDefault && !a.archived),
  ...accounts.where((a) => !(a.isDefault && !a.archived)),
];

class Category {
  final String id;
  String name;
  String icon;
  int color;
  TxType kind; // expense or income
  bool isCustom;
  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.kind,
    this.isCustom = false,
  });

  IconData get iconData => categoryIcons[icon] ?? Icons.category;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'kind': kind.name,
    'is_custom': isCustom ? 1 : 0,
  };

  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: m['id'] as String,
    name: m['name'] as String,
    icon: m['icon'] as String,
    color: (m['color'] as num).toInt(),
    kind: TxType.values.byName(m['kind'] as String),
    isCustom: (m['is_custom'] as num) == 1,
  );
}

class Tx {
  final String id;
  TxType type;
  int amount; // paise, always positive
  String accountId;
  String? toAccountId; // transfers only
  String? categoryId;
  String note;
  DateTime date;
  String? receipt; // encrypted file name
  String? recurringId;
  Tx({
    required this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    required this.date,
    this.receipt,
    this.recurringId,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'category_id': categoryId,
    'note': note,
    'date': date.millisecondsSinceEpoch,
    'receipt': receipt,
    'recurring_id': recurringId,
  };

  factory Tx.fromMap(Map<String, Object?> m) => Tx(
    id: m['id'] as String,
    type: TxType.values.byName(m['type'] as String),
    amount: (m['amount'] as num).toInt(),
    accountId: m['account_id'] as String,
    toAccountId: m['to_account_id'] as String?,
    categoryId: m['category_id'] as String?,
    note: (m['note'] as String?) ?? '',
    date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
    receipt: m['receipt'] as String?,
    recurringId: m['recurring_id'] as String?,
  );
}

class Recurring {
  final String id;
  String title;
  TxType type; // expense or income
  int amount;
  String accountId;
  String? categoryId;
  Frequency frequency;
  DateTime nextDue;
  int anchorDay; // day-of-month for monthly rules
  DateTime? endDate;
  bool active;
  Recurring({
    required this.id,
    required this.title,
    required this.type,
    required this.amount,
    required this.accountId,
    this.categoryId,
    required this.frequency,
    required this.nextDue,
    required this.anchorDay,
    this.endDate,
    this.active = true,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'type': type.name,
    'amount': amount,
    'account_id': accountId,
    'category_id': categoryId,
    'frequency': frequency.name,
    'next_due': nextDue.millisecondsSinceEpoch,
    'anchor_day': anchorDay,
    'end_date': endDate?.millisecondsSinceEpoch,
    'active': active ? 1 : 0,
  };

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
    id: m['id'] as String,
    title: m['title'] as String,
    type: TxType.values.byName(m['type'] as String),
    amount: (m['amount'] as num).toInt(),
    accountId: m['account_id'] as String,
    categoryId: m['category_id'] as String?,
    frequency: Frequency.values.byName(m['frequency'] as String),
    nextDue: DateTime.fromMillisecondsSinceEpoch(
      (m['next_due'] as num).toInt(),
    ),
    anchorDay: (m['anchor_day'] as num).toInt(),
    endDate: m['end_date'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['end_date'] as num).toInt()),
    active: (m['active'] as num) == 1,
  );
}

DateTime nextOccurrence(DateTime d, Frequency f, {int? anchorDay}) {
  switch (f) {
    case Frequency.daily:
      return DateTime(d.year, d.month, d.day + 1);
    case Frequency.weekly:
      return DateTime(d.year, d.month, d.day + 7);
    case Frequency.monthly:
      final day = anchorDay ?? d.day;
      final lastDay = DateTime(d.year, d.month + 2, 0).day;
      return DateTime(d.year, d.month + 1, day > lastDay ? lastDay : day);
    case Frequency.yearly:
      final lastDay = DateTime(d.year + 1, d.month + 1, 0).day;
      return DateTime(d.year + 1, d.month, d.day > lastDay ? lastDay : d.day);
  }
}
