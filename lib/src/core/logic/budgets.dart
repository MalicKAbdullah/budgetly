import 'package:flutter/foundation.dart' show immutable;
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/models/txn.dart';

/// A category's spend against its monthly budget, for one month.
@immutable
final class CategorySpend {
  const CategorySpend({
    required this.categoryId,
    required this.name,
    required this.budgetMinor,
    required this.spentMinor,
  });

  final String categoryId;
  final String name;
  final int budgetMinor;
  final int spentMinor;

  bool get hasBudget => budgetMinor > 0;
  int get remainingMinor => budgetMinor - spentMinor;
  bool get overBudget => budgetMinor > 0 && spentMinor > budgetMinor;

  /// 0..1 for progress bars (0 when no budget is set).
  double get progress {
    if (budgetMinor <= 0) return 0;
    final r = spentMinor / budgetMinor;
    if (r.isNaN) return 0;
    return r.clamp(0.0, 1.0).toDouble();
  }
}

/// Pure monthly roll-ups. "Spend" only ever counts [TxnType.expense]; income
/// and transfers are excluded so moving cash around never looks like spending.
abstract final class Budgets {
  static bool inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  // "Spend" uses the owner's own share (amount minus any reimbursable part),
  // so money fronted for friends isn't counted as the owner's spending.
  static int spentInMonthMinor(
    AppData data,
    String categoryId,
    DateTime month,
  ) => data.txns
      .where(
        (t) =>
            t.type == TxnType.expense &&
            t.categoryId == categoryId &&
            inMonth(t.date, month),
      )
      .fold(0, (sum, t) => sum + t.ownShareMinor);

  static int totalSpentInMonthMinor(AppData data, DateTime month) => data.txns
      .where((t) => t.type == TxnType.expense && inMonth(t.date, month))
      .fold(0, (sum, t) => sum + t.ownShareMinor);

  // Repayments (income tagged reimbursesTxnId) are not real income.
  static int totalIncomeInMonthMinor(AppData data, DateTime month) => data.txns
      .where(
        (t) =>
            t.type == TxnType.income &&
            !t.isReimbursement &&
            inMonth(t.date, month),
      )
      .fold(0, (sum, t) => sum + t.amountMinor);

  static int totalMonthlyBudgetMinor(AppData data) =>
      data.categories.fold(0, (sum, c) => sum + c.monthlyBudgetMinor);

  /// Per-category spend for [month], most-spent first. Includes categories
  /// with zero spend so their budgets still show.
  static List<CategorySpend> byCategory(AppData data, DateTime month) {
    final rows =
        data.categories
            .map(
              (c) => CategorySpend(
                categoryId: c.id,
                name: c.name,
                budgetMinor: c.monthlyBudgetMinor,
                spentMinor: spentInMonthMinor(data, c.id, month),
              ),
            )
            .toList()
          ..sort((a, b) => b.spentMinor.compareTo(a.spentMinor));
    return rows;
  }

  /// Expense this month not attributed to any (existing) category.
  static int uncategorizedSpentMinor(AppData data, DateTime month) {
    final ids = data.categories.map((c) => c.id).toSet();
    return data.txns
        .where(
          (t) =>
              t.type == TxnType.expense &&
              inMonth(t.date, month) &&
              !ids.contains(t.categoryId),
        )
        .fold(0, (sum, t) => sum + t.ownShareMinor);
  }
}
