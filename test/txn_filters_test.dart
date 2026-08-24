import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';

void main() {
  final t0 = DateTime(2026, 8, 1);
  final bank = Account(
    id: 'bank',
    name: 'Meezan',
    type: AccountType.bank,
    createdAt: t0,
  );
  final cash = Account(
    id: 'cash',
    name: 'Cash',
    type: AccountType.cash,
    createdAt: t0,
  );
  final food = Category(id: 'food', name: 'Groceries', createdAt: t0);
  final fuel = Category(id: 'fuel', name: 'Fuel', createdAt: t0);

  Txn txn({
    required String id,
    TxnType type = TxnType.expense,
    int amount = 1000,
    required int day,
    String account = 'bank',
    String? toAccount,
    String? category,
    String note = '',
  }) => Txn(
    id: id,
    type: type,
    amountMinor: amount,
    date: DateTime(2026, 8, day),
    accountId: account,
    toAccountId: toAccount,
    categoryId: category,
    note: note,
    createdAt: t0,
  );

  final data = AppData(
    accounts: [bank, cash],
    categories: [food, fuel],
    txns: [
      txn(id: 'a', day: 2, category: 'food', note: 'Imtiaz run'),
      txn(id: 'b', day: 4, category: 'fuel', note: 'PSO'),
      txn(id: 'c', day: 6, category: 'food', account: 'cash', note: 'Sabzi'),
      txn(id: 'd', day: 8, note: 'Mystery charge'),
      txn(id: 'e', day: 10, type: TxnType.income, note: 'Salary'),
      txn(
        id: 'f',
        day: 12,
        type: TxnType.transfer,
        account: 'bank',
        toAccount: 'cash',
        note: 'ATM',
      ),
      // Outside the window used below.
      txn(id: 'old', day: 1, category: 'food', note: 'Last month'),
    ],
  );

  final start = DateTime(2026, 8, 2);
  final end = DateTime(2026, 8, 12);

  List<String> ids(TxnFilters f) =>
      f.apply(data, start: start, end: end).map((t) => t.id).toList();

  test('no filters: everything in the window, newest first', () {
    expect(ids(const TxnFilters()), ['f', 'e', 'd', 'c', 'b', 'a']);
    expect(const TxnFilters().isActive, isFalse);
  });

  test('the date window still bounds every other filter', () {
    expect(ids(const TxnFilters(categoryId: 'food')), ['c', 'a']);
    expect(
      const TxnFilters(
        categoryId: 'food',
      ).apply(data, start: DateTime(2026, 8, 1), end: end).map((t) => t.id),
      ['c', 'a', 'old'],
    );
  });

  test('category filter narrows to one category', () {
    expect(ids(const TxnFilters(categoryId: 'fuel')), ['b']);
    expect(const TxnFilters(categoryId: 'fuel').isActive, isTrue);
  });

  test('uncategorized is filterable with the empty-string id', () {
    // Income and transfers carry no category either, so they belong to the
    // same bucket the dashboard shows as "Uncategorized".
    expect(ids(const TxnFilters(categoryId: '')), ['f', 'e', 'd']);
  });

  test('category combines with type', () {
    expect(ids(const TxnFilters(categoryId: '', type: TxnType.expense)), ['d']);
    expect(
      ids(const TxnFilters(categoryId: 'food', type: TxnType.income)),
      isEmpty,
    );
  });

  test('category combines with account, transfers matching either side', () {
    expect(ids(const TxnFilters(categoryId: 'food', accountId: 'cash')), ['c']);
    expect(ids(const TxnFilters(accountId: 'cash')), ['f', 'c']);
  });

  test('category combines with search', () {
    expect(ids(const TxnFilters(categoryId: 'food', search: 'sabzi')), ['c']);
    expect(ids(const TxnFilters(categoryId: 'food', search: 'pso')), isEmpty);
  });

  test('search matches note, category name and account name', () {
    expect(ids(const TxnFilters(search: 'mystery')), ['d']);
    expect(ids(const TxnFilters(search: 'groceries')), ['c', 'a']);
    expect(ids(const TxnFilters(search: 'meezan')), ['f', 'e', 'd', 'b', 'a']);
    // Blank search is no search.
    expect(const TxnFilters(search: '   ').isActive, isFalse);
    expect(ids(const TxnFilters(search: '   ')).length, 6);
  });

  test('all four at once', () {
    expect(
      ids(
        const TxnFilters(
          type: TxnType.expense,
          accountId: 'bank',
          categoryId: 'food',
          search: 'imtiaz',
        ),
      ),
      ['a'],
    );
  });

  test('a category with nothing in it yields an empty list, not an error', () {
    expect(ids(const TxnFilters(categoryId: 'no-such-category')), isEmpty);
  });

  test('copyWith clears individual filters', () {
    const f = TxnFilters(
      type: TxnType.expense,
      accountId: 'bank',
      categoryId: 'food',
      search: 'x',
    );
    expect(f.copyWith(clearCategory: true).categoryId, isNull);
    expect(f.copyWith(clearCategory: true).type, TxnType.expense);
    expect(f.copyWith(clearType: true, clearAccount: true).isActive, isTrue);
    expect(
      f
          .copyWith(
            clearType: true,
            clearAccount: true,
            clearCategory: true,
            search: '',
          )
          .isActive,
      isFalse,
    );
  });
}
