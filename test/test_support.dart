import 'package:silentwallet/core/models.dart';
import 'package:silentwallet/core/repo.dart';
import 'package:silentwallet/core/search.dart';

/// A Repo that never touches the (native, encrypted) database. The query
/// methods read from [txs]; accounts / categories are plain public lists.
class FakeRepo extends Repo {
  List<Tx> txs;
  FakeRepo({this.txs = const []});

  @override
  Future<List<Tx>> allTx() async =>
      [...txs]..sort((a, b) => b.date.compareTo(a.date));

  @override
  Future<List<Tx>> txBetween(DateTime from, DateTime to,
          {String? accountId, String? categoryId, String? search}) async =>
      (await allTx())
          .where((t) => !t.date.isBefore(from) && t.date.isBefore(to))
          .toList();

  @override
  Future<Map<String, int>> balances() async => {};

  @override
  Future<List<NoteEntry>> noteHistory() async => buildNoteHistory(txs.map(
      (t) => (note: t.note, categoryId: t.categoryId, date: t.date)));

  @override
  Future<int> processRecurring() async => 0;
}

const defaultExpenseNames = [
  'Food & Dining', 'Groceries', 'Shopping', 'Transport', 'Fuel', 'Rent & Home',
  'Bills & Utilities', 'Mobile & Internet', 'Health', 'Education',
  'Entertainment', 'Travel', 'Gifts', 'Other',
];

List<Category> sampleCategories({int extraCustom = 0}) => [
      for (var i = 0; i < defaultExpenseNames.length; i++)
        Category(
            id: 'e$i',
            name: defaultExpenseNames[i],
            icon: 'other',
            color: 0xFF64B5F6,
            kind: TxType.expense),
      for (var i = 0; i < extraCustom; i++)
        Category(
            id: 'x$i',
            name: 'Custom tag $i',
            icon: 'other',
            color: 0xFF81C784,
            kind: TxType.expense,
            isCustom: true),
      Category(
          id: 'i1', name: 'Salary', icon: 'salary', color: 0xFF81C784, kind: TxType.income),
    ];

List<Account> sampleAccounts() => [
      Account(id: 'a1', name: 'Cash', type: 'Cash'),
      Account(id: 'a2', name: 'HDFC Savings', type: 'Bank'),
    ];

Tx sampleTx(String id, DateTime date,
        {String note = '', int paise = 10000, String? categoryId, String accountId = 'a1'}) =>
    Tx(
        id: id,
        type: TxType.expense,
        amount: paise,
        accountId: accountId,
        categoryId: categoryId,
        note: note,
        date: date);
