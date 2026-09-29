import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';

/// The aggregate numbers the home-screen widgets show, already formatted.
/// Only totals ever leave the encrypted vault — never a transaction, note or
/// person name. With amounts hidden every figure is masked and the progress
/// bar (which would leak the spent ratio) is dropped.
final class WidgetSnapshot {
  const WidgetSnapshot({
    required this.monthLabel,
    required this.primaryLabel,
    required this.primaryValue,
    required this.spentValue,
    required this.budgetValue,
    required this.progressPercent,
    required this.showBar,
    required this.overBudget,
    required this.categories,
    required this.owedValue,
  });

  static const String mask = '••••';

  final String monthLabel;

  /// "Left to spend" with a budget, "Spent this month" without one.
  final String primaryLabel;
  final String primaryValue;
  final String spentValue;

  /// "of Rs 50,000" — empty when no monthly budget is set.
  final String budgetValue;
  final int progressPercent;
  final bool showBar;
  final bool overBudget;

  /// Up to three (name, amount) rows, most-spent first.
  final List<({String name, String amount})> categories;
  final String owedValue;

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  factory WidgetSnapshot.from(
    AppData data,
    DateTime now, {
    required bool showAmounts,
  }) {
    final month = DateTime(now.year, now.month);
    final code = data.currencyCode;
    String fmt(int minor) =>
        showAmounts ? Money.format(minor, code: code) : mask;

    final spent = Budgets.totalSpentInMonthMinor(data, month);
    final budget = Budgets.totalMonthlyBudgetMinor(data);
    final hasBudget = budget > 0;
    final left = budget - spent;

    final top = Budgets.byCategory(
      data,
      month,
    ).where((c) => c.spentMinor > 0).take(3);

    return WidgetSnapshot(
      monthLabel: _months[month.month - 1],
      primaryLabel: hasBudget ? 'Left to spend' : 'Spent this month',
      primaryValue: fmt(hasBudget ? left : spent),
      spentValue: fmt(spent),
      budgetValue: hasBudget ? 'of ${fmt(budget)}' : '',
      progressPercent: hasBudget
          ? (spent * 100 / budget).clamp(0, 100).round()
          : 0,
      showBar: showAmounts && hasBudget,
      overBudget: hasBudget && spent > budget,
      categories: [
        for (final c in top) (name: c.name, amount: fmt(c.spentMinor)),
      ],
      owedValue: fmt(PeopleLedger.totalOwedToYouMinor(data)),
    );
  }
}
