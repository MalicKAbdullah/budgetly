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

import 'perf/perf_data.dart';

/// Every figure of [DashboardSummary] against the straightforward roll-ups the
/// dashboard is defined by, on random 5,000-transaction vaults.
void main() {
  final dataDay = DateTime(2026, 10, 27);
  final vaults = {
    for (final seed in [1, 2, 3]) seed: perfData(today: dataDay, seed: seed),
  };
  final days = [
    dataDay,
    DateTime(2026, 3, 1),
    DateTime(2026, 3, 31),
    DateTime(2025, 12, 31),
    DateTime(2026, 1, 1),
    DateTime(2024, 2, 29),
    DateTime(2026, 11, 2),
  ];
  final filters = [
    const PeriodFilter.thisMonth(),
    const PeriodFilter(PeriodPreset.last3Months),
    const PeriodFilter(PeriodPreset.last6Months),
    const PeriodFilter(PeriodPreset.thisYear),
    const PeriodFilter(PeriodPreset.allTime),
    PeriodFilter.range(DateTime(2026, 10, 3), DateTime(2026, 10, 12)),
    PeriodFilter.range(DateTime(2026, 8, 20), DateTime(2026, 10, 5)),
    PeriodFilter.range(DateTime(2025, 2, 10), DateTime(2026, 6, 30)),
    PeriodFilter.range(DateTime(2019, 1, 1), DateTime(2026, 12, 31)),
    PeriodFilter.range(DateTime(2010, 1, 1), DateTime(2012, 1, 1)),
    // Stored out of order: no range figures, chart over the ordered window.
    PeriodFilter(
      PeriodPreset.custom,
      customStart: DateTime(2026, 9, 30),
      customEnd: DateTime(2026, 9, 1),
    ),
  ];

  void expectBuckets(List<SpendBucket> a, List<SpendBucket> b) {
    expect(a.map((x) => (x.label, x.minor)), b.map((x) => (x.label, x.minor)));
  }

  void expectSummary(AppData data, PeriodFilter filter, DateTime today) {
    final s = DashboardSummary.compute(data, filter, today);
    final (start, end) = filter.resolve(today);
    expect((s.start, s.end), (start, end));

    // Range figures.
    expect(s.spentMinor, DashboardFlow.spentInRange(data, start, end));
    expect(s.incomeMinor, DashboardFlow.incomeInRange(data, start, end));
    expect(
      s.spendByCategory.map((e) => (e.key, e.value)),
      DashboardFlow.spendByCategory(
        data,
        start,
        end,
      ).map((e) => (e.key, e.value)),
    );
    expectBuckets(s.buckets, DashboardFlow.spendBuckets(data, start, end));
    expect(
      s.accountFlows.map((f) => (f.accountId, f.name, f.inMinor, f.outMinor)),
      DashboardFlow.byAccount(
        data,
        start,
        end,
      ).map((f) => (f.accountId, f.name, f.inMinor, f.outMinor)),
    );

    // Month.
    final month = DateTime(today.year, today.month);
    expect(s.monthSpentMinor, Budgets.totalSpentInMonthMinor(data, month));
    expect(s.monthIncomeMinor, Budgets.totalIncomeInMonthMinor(data, month));
    expect(s.monthlyBudgetMinor, Budgets.totalMonthlyBudgetMinor(data));
    final lastStart = DateTime(today.year, today.month - 1);
    final lastDays = DateTime(today.year, today.month, 0).day;
    final lastEnd = DateTime(
      lastStart.year,
      lastStart.month,
      today.day < lastDays ? today.day : lastDays,
    );
    expect(
      s.lastMonthToDateSpentMinor,
      DashboardFlow.spentInRange(data, lastStart, lastEnd),
    );
    expect(
      s.budgetRows.map((r) => (r.categoryId, r.spentMinor, r.budgetMinor)),
      Budgets.byCategory(data, month)
          .where((c) => c.hasBudget || c.spentMinor > 0)
          .map((r) => (r.categoryId, r.spentMinor, r.budgetMinor)),
    );

    // Week.
    final weekDays = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    expect(s.weekDays, weekDays);
    expect(s.weekSpentMinor, [
      for (final d in weekDays) DashboardFlow.spentInRange(data, d, d),
    ]);
    expect(
      s.weekBeforeSpentMinor,
      DashboardFlow.spentInRange(
        data,
        today.subtract(const Duration(days: 13)),
        today.subtract(const Duration(days: 7)),
      ),
    );

    // Recent: the same dates as a full sort, and on a tie the later entry.
    final sorted = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
    expect(s.recent.map((t) => t.date), sorted.take(4).map((t) => t.date));
    for (var i = 1; i < s.recent.length; i++) {
      if (s.recent[i].date == s.recent[i - 1].date) {
        expect(
          data.txns.indexOf(s.recent[i]),
          lessThan(data.txns.indexOf(s.recent[i - 1])),
        );
      }
    }
    expect(s.todayCount, sorted.where((t) => !t.date.isBefore(today)).length);

    // People and money.
    expect(
      s.openPeople.map((p) => (p.key, p.owedToYouMinor, p.youOweMinor)),
      PeopleLedger.openPositions(
        data,
      ).map((p) => (p.key, p.owedToYouMinor, p.youOweMinor)),
    );
    expect(s.owedToYouMinor, PeopleLedger.totalOwedToYouMinor(data));
    expect(s.youOweMinor, PeopleLedger.totalYouOweMinor(data));
    for (final a in data.accounts) {
      expect(s.accountBalances[a.id], Balances.accountBalanceMinor(data, a.id));
    }
    expect(s.netWorthMinor, Balances.netWorthMinor(data));
    final savings = Savings.position(data);
    expect(
      (
        s.savings.heldMinor,
        s.savings.countedReceivablesMinor,
        s.savings.uncountedReceivablesMinor,
        s.savings.targetMinor,
      ),
      (
        savings.heldMinor,
        savings.countedReceivablesMinor,
        savings.uncountedReceivablesMinor,
        savings.targetMinor,
      ),
    );

    // The home-screen widget reads the same month figures.
    for (final showAmounts in [true, false]) {
      final a = WidgetSnapshot.from(data, today, showAmounts: showAmounts);
      final b = WidgetSnapshot.fromSummary(
        s,
        code: data.currencyCode,
        showAmounts: showAmounts,
      );
      expect(
        (
          b.monthLabel,
          b.primaryLabel,
          b.primaryValue,
          b.spentValue,
          b.budgetValue,
          b.progressPercent,
          b.showBar,
          b.overBudget,
          b.owedValue,
        ),
        (
          a.monthLabel,
          a.primaryLabel,
          a.primaryValue,
          a.spentValue,
          a.budgetValue,
          a.progressPercent,
          a.showBar,
          a.overBudget,
          a.owedValue,
        ),
      );
      expect(b.categories, a.categories);
    }
  }

  for (final MapEntry(key: seed, value: data) in vaults.entries) {
    test('seed $seed: every filter on every day matches the roll-ups', () {
      for (final today in days) {
        for (final filter in filters) {
          expectSummary(data, filter, today);
        }
      }
    });
  }

  test('an empty vault and a vault with no expenses', () {
    final data = vaults[1]!;
    for (final d in [
      const AppData(),
      data.copyWith(txns: const []),
      data.copyWith(
        txns: data.txns.where((t) => t.type.name != 'expense').toList(),
      ),
    ]) {
      for (final filter in filters) {
        expectSummary(d, filter, dataDay);
      }
    }
  });
}
