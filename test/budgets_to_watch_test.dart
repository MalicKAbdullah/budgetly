import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/features/dashboard/widgets/home_hero.dart';
import 'package:flutter_test/flutter_test.dart';

CategorySpend _row(String name, int budget, int spent) => CategorySpend(
  categoryId: name,
  name: name,
  budgetMinor: budget,
  spentMinor: spent,
);

void main() {
  test('only budgets over, near the limit or ahead of pace, worst first', () {
    // Day 10 of a 30-day month: pace is a third of each budget.
    final now = DateTime(2026, 11, 10);
    final rows = [
      _row('on track', 1000, 200),
      _row('half, ahead of pace', 1000, 550),
      _row('near limit', 1000, 850),
      _row('over', 1000, 1200),
      _row('fixed bill paid', 1000, 1000),
      _row('no budget', 0, 5000),
    ];
    expect(BudgetPair.atRisk(rows, now).map((r) => r.name), [
      'over',
      'near limit',
      'half, ahead of pace',
    ]);
  });

  test('half spent but behind pace late in the month is not at risk', () {
    final now = DateTime(2026, 11, 25);
    expect(BudgetPair.atRisk([_row('groceries', 1000, 600)], now), isEmpty);
  });
}
