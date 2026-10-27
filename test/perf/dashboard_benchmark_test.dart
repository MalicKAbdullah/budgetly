import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/dashboard_summary.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/features/home_widget/widget_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench.dart';
import 'naive_flow.dart';
import 'perf_data.dart';

/// Every roll-up one dashboard build ran when each card computed its own
/// figures, with [NaiveFlow] (three DateTimes per range check) — once per
/// build, plus the home-screen widget snapshot on each data change.
Object perWidgetBuild(AppData data, PeriodFilter filter, DateTime now) {
  final month = DateTime(now.year, now.month);
  final (start, end) = filter.resolve(now);
  final today = DateTime(now.year, now.month, now.day);
  // Dashboard body.
  final out = <Object>[
    NaiveFlow.spentInRange(data, start, end),
    NaiveFlow.incomeInRange(data, start, end),
    NaiveFlow.spendBuckets(data, start, end),
    NaiveFlow.byAccount(data, start, end),
    Budgets.byCategory(data, month),
    ([...data.txns]..sort((a, b) => b.date.compareTo(a.date))).take(4),
    PeopleLedger.openPositions(data),
    // Month hero.
    Budgets.totalSpentInMonthMinor(data, month),
    Budgets.totalIncomeInMonthMinor(data, month),
    Budgets.totalMonthlyBudgetMinor(data),
    NaiveFlow.spentInRange(
      data,
      DateTime(now.year, now.month - 1),
      DateTime(
        now.year,
        now.month - 1,
        now.day < DateTime(now.year, now.month, 0).day
            ? now.day
            : DateTime(now.year, now.month, 0).day,
      ),
    ),
    // People section.
    PeopleLedger.totalOwedToYouMinor(data),
    PeopleLedger.totalYouOweMinor(data),
    // Category breakdown.
    NaiveFlow.spendByCategory(data, start, end),
    // Week card.
    for (var i = 6; i >= 0; i--)
      () {
        final d = today.subtract(Duration(days: i));
        return NaiveFlow.spentInRange(data, d, d);
      }(),
    NaiveFlow.spentInRange(
      data,
      today.subtract(const Duration(days: 13)),
      today.subtract(const Duration(days: 7)),
    ),
    // Savings and accounts cards.
    Savings.position(data),
    Balances.netWorthMinor(data),
    for (final a in data.activeAccounts)
      Balances.accountBalanceMinor(data, a.id),
  ];
  return out;
}

void main() {
  test('dashboard figures, 5,000 transactions', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final data = perfData(today: today);
    final rows = <String, double>{};
    for (final filter in const [
      PeriodFilter.thisMonth(),
      PeriodFilter(PeriodPreset.allTime),
    ]) {
      final name = filter.preset.label;
      rows['$name: per-widget roll-ups, every build'] = await medianMs(
        () async => perWidgetBuild(data, filter, now),
      );
      rows['$name: DashboardSummary, once per data/filter/day'] =
          await medianMs(
            () async => DashboardSummary.compute(data, filter, today),
            runs: 31,
          );
    }
    rows['home widget: WidgetSnapshot.from'] = await medianMs(
      () async => WidgetSnapshot.from(data, now, showAmounts: true),
    );
    final summary = DashboardSummary.compute(
      data,
      const PeriodFilter.thisMonth(),
      today,
    );
    rows['home widget: WidgetSnapshot.fromSummary'] = await medianMs(
      () async => WidgetSnapshot.fromSummary(
        summary,
        code: data.currencyCode,
        showAmounts: true,
      ),
      runs: 31,
    );
    rows['activity filter: DashboardFlow.spentInRange, all time'] =
        await medianMs(
          () async => DashboardFlow.spentInRange(
            data,
            DateTime(1970),
            DateTime(2999, 12, 31),
          ),
        );
    rows['activity filter: NaiveFlow.spentInRange, all time'] = await medianMs(
      () async =>
          NaiveFlow.spentInRange(data, DateTime(1970), DateTime(2999, 12, 31)),
    );
    report('dashboard, ${data.txns.length} txns', rows);

    expect(
      rows['This month: DashboardSummary, once per data/filter/day']!,
      lessThan(rows['This month: per-widget roll-ups, every build']!),
    );
  });
}
