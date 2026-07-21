import 'package:flutter_test/flutter_test.dart';
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/logic/balances.dart';
import 'package:tally/src/core/logic/budgets.dart';
import 'package:tally/src/core/models/account.dart';
import 'package:tally/src/core/models/category.dart';
import 'package:tally/src/core/models/txn.dart';

void main() {
  final created = DateTime(2026, 1, 1);
  final thisMonth = DateTime(2026, 7, 1);
  final lastMonth = DateTime(2026, 6, 15);

  final data = AppData(
    accounts: [
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 10000,
        createdAt: created,
      ),
      Account(
        id: 'bank',
        name: 'Meezan',
        type: AccountType.bank,
        createdAt: created,
      ),
    ],
    categories: [
      Category(
        id: 'groc',
        name: 'Groceries',
        monthlyBudgetMinor: 10000,
        createdAt: created,
      ),
      Category(id: 'fuel', name: 'Fuel', createdAt: created),
    ],
    txns: [
      Txn(
        id: 't1',
        type: TxnType.expense,
        amountMinor: 3000,
        date: DateTime(2026, 7, 5),
        accountId: 'cash',
        categoryId: 'groc',
        createdAt: created,
      ),
      Txn(
        id: 't2',
        type: TxnType.income,
        amountMinor: 50000,
        date: DateTime(2026, 7, 2),
        accountId: 'bank',
        createdAt: created,
      ),
      Txn(
        id: 't3',
        type: TxnType.transfer,
        amountMinor: 20000,
        date: DateTime(2026, 7, 3),
        accountId: 'bank',
        toAccountId: 'cash',
        createdAt: created,
      ),
      Txn(
        id: 't4',
        type: TxnType.expense,
        amountMinor: 5000,
        date: lastMonth,
        accountId: 'bank',
        categoryId: 'fuel',
        createdAt: created,
      ),
    ],
  );

  group('Balances', () {
    test('account balances include opening + expense/income/transfer', () {
      // cash: 100 - 30 (expense) + 200 (transfer in) = 270
      expect(Balances.accountBalanceMinor(data, 'cash'), 27000);
      // bank: 0 + 500 (income) - 200 (transfer out) - 50 (expense) = 250
      expect(Balances.accountBalanceMinor(data, 'bank'), 25000);
    });

    test('net worth sums active accounts', () {
      expect(Balances.netWorthMinor(data), 52000);
    });
  });

  group('Budgets', () {
    test('monthly spend counts only expenses in that month', () {
      // This month: only the 30 groceries expense (income/transfer excluded,
      // fuel is last month).
      expect(Budgets.totalSpentInMonthMinor(data, thisMonth), 3000);
      expect(Budgets.spentInMonthMinor(data, 'groc', thisMonth), 3000);
      expect(Budgets.spentInMonthMinor(data, 'fuel', thisMonth), 0);
    });

    test('income is separate from spend', () {
      expect(Budgets.totalIncomeInMonthMinor(data, thisMonth), 50000);
    });

    test('category budget status', () {
      final rows = Budgets.byCategory(data, thisMonth);
      final groc = rows.firstWhere((r) => r.categoryId == 'groc');
      expect(groc.spentMinor, 3000);
      expect(groc.overBudget, isFalse);
      expect(groc.remainingMinor, 7000);
      expect(groc.progress, closeTo(0.3, 0.001));
    });
  });
}
