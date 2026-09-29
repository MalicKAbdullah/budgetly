import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/features/home_widget/widget_snapshot.dart';

void main() {
  final created = DateTime(2026, 1, 1);
  final now = DateTime(2026, 7, 20);

  AppData build({int budget = 10000}) => AppData(
    accounts: [
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        createdAt: created,
      ),
    ],
    categories: [
      Category(
        id: 'groc',
        name: 'Groceries',
        monthlyBudgetMinor: budget,
        createdAt: created,
      ),
    ],
    txns: [
      Txn(
        id: 't1',
        type: TxnType.expense,
        amountMinor: 2500,
        date: DateTime(2026, 7, 5),
        accountId: 'cash',
        categoryId: 'groc',
        createdAt: created,
      ),
    ],
  );

  test('shows what is left against the budget', () {
    final s = WidgetSnapshot.from(build(), now, showAmounts: true);
    expect(s.primaryLabel, 'Left to spend');
    expect(s.primaryValue, contains('75'));
    expect(s.progressPercent, 25);
    expect(s.showBar, isTrue);
    expect(s.categories.single.name, 'Groceries');
  });

  test('without a budget it shows the month spend and no bar', () {
    final s = WidgetSnapshot.from(build(budget: 0), now, showAmounts: true);
    expect(s.primaryLabel, 'Spent this month');
    expect(s.showBar, isFalse);
    expect(s.budgetValue, isEmpty);
  });

  test('hidden amounts are masked everywhere and the bar is dropped', () {
    final s = WidgetSnapshot.from(build(), now, showAmounts: false);
    expect(s.primaryValue, WidgetSnapshot.mask);
    expect(s.spentValue, WidgetSnapshot.mask);
    expect(s.owedValue, WidgetSnapshot.mask);
    expect(s.categories.single.amount, WidgetSnapshot.mask);
    expect(s.showBar, isFalse);
  });
}
