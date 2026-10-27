import 'package:flutter/foundation.dart' show immutable;
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// Every figure the dashboard shows, derived from one snapshot of the data,
/// the shared date filter and the calendar day.
///
/// Each value equals what the straightforward roll-up in [DashboardFlow],
/// [Budgets], [Balances], [PeopleLedger] and [Savings] returns for the same
/// inputs; [compute] gets there in one pass over the transactions, keeping
/// per-day totals keyed by [DashboardFlow.dayKey].
@immutable
final class DashboardSummary {
  const DashboardSummary({
    required this.today,
    required this.start,
    required this.end,
    required this.monthSpentMinor,
    required this.monthIncomeMinor,
    required this.monthlyBudgetMinor,
    required this.lastMonthToDateSpentMinor,
    required this.budgetRows,
    required this.weekDays,
    required this.weekSpentMinor,
    required this.weekBeforeSpentMinor,
    required this.recent,
    required this.todayCount,
    required this.openPeople,
    required this.owedToYouMinor,
    required this.youOweMinor,
    required this.spentMinor,
    required this.incomeMinor,
    required this.spendByCategory,
    required this.buckets,
    required this.accountFlows,
    required this.accountBalances,
    required this.netWorthMinor,
    required this.savings,
  });

  /// Midnight of the day the summary describes.
  final DateTime today;

  /// The filter window, resolved against [today].
  final DateTime start;
  final DateTime end;

  // -- The calendar month of [today] (budgets are per month) ---------------

  final int monthSpentMinor;
  final int monthIncomeMinor;
  final int monthlyBudgetMinor;

  /// Spent over the same days of last month, so a half-gone month is never
  /// compared with a whole one.
  final int lastMonthToDateSpentMinor;

  /// [Budgets.byCategory] rows that have a budget or some spend.
  final List<CategorySpend> budgetRows;

  // -- The last seven days -------------------------------------------------

  /// Oldest first; the last one is today.
  final List<DateTime> weekDays;
  final List<int> weekSpentMinor;

  /// Spent over the seven days before [weekDays].
  final int weekBeforeSpentMinor;

  // -- Recent activity and people ------------------------------------------

  /// The four latest transactions, newest first; among equal dates the one
  /// recorded later comes first.
  final List<Txn> recent;

  /// Transactions dated today or later.
  final int todayCount;

  final List<PersonPosition> openPeople;
  final int owedToYouMinor;
  final int youOweMinor;

  // -- The filter window ---------------------------------------------------

  final int spentMinor;
  final int incomeMinor;
  final List<MapEntry<String, int>> spendByCategory;
  final List<SpendBucket> buckets;
  final List<AccountFlow> accountFlows;

  // -- Money ---------------------------------------------------------------

  /// Current balance of every account, archived ones included.
  final Map<String, int> accountBalances;
  final int netWorthMinor;
  final SavingsPosition savings;

  static DateTime _fromKey(int key) =>
      DateTime(key ~/ 10000, key ~/ 100 % 100, key % 100);

  static int _sumDays(Map<int, int> byDay, int from, int to) {
    var sum = 0;
    for (final MapEntry(:key, :value) in byDay.entries) {
      if (key >= from && key <= to) sum += value;
    }
    return sum;
  }

  static DashboardSummary compute(
    AppData data,
    PeriodFilter filter,
    DateTime today,
  ) {
    assert(
      today == DateTime(today.year, today.month, today.day),
      'today is a calendar day',
    );
    final (start, end) = filter.resolve(today);
    final startKey = DashboardFlow.dayKey(start);
    final endKey = DashboardFlow.dayKey(end);
    final todayKey = DashboardFlow.dayKey(today);
    final monthKey = today.year * 100 + today.month;

    // The chart window is the filter window put in order.
    final chartLo = startKey <= endKey ? startKey : endKey;
    final chartHi = startKey <= endKey ? endKey : startKey;
    var chartFirstExpense = 0;
    var chartLastExpense = 0;

    // Own-share spending per day, month and year (settlements excluded).
    final spendByDay = <int, int>{};
    final spendByMonth = <int, int>{};
    final spendByYear = <int, int>{};

    var monthSpent = 0;
    var monthIncome = 0;
    final monthByCategory = <String, int>{};

    var spent = 0;
    var income = 0;
    final byCategory = <String, int>{};

    final active = data.activeAccounts;
    final inByAccount = <String, int>{for (final a in active) a.id: 0};
    final outByAccount = <String, int>{for (final a in active) a.id: 0};
    final balances = <String, int>{
      for (final a in data.accounts) a.id: a.openingBalanceMinor,
    };

    var todayCount = 0;
    // The latest four as (date, index), newest first.
    final recent = <(DateTime, int)>[];

    final txns = data.txns;
    for (var i = 0; i < txns.length; i++) {
      final t = txns[i];
      final date = t.date;
      final key = DashboardFlow.dayKey(date);
      final inWindow = key >= startKey && key <= endKey;
      if (key >= todayKey) todayCount++;

      switch (t.type) {
        case TxnType.expense:
          if (key >= chartLo && key <= chartHi) {
            if (chartFirstExpense == 0 || key < chartFirstExpense) {
              chartFirstExpense = key;
            }
            if (key > chartLastExpense) chartLastExpense = key;
          }
          if (!t.isSettlement) {
            final own = t.ownShareMinor;
            spendByDay[key] = (spendByDay[key] ?? 0) + own;
            final month = key ~/ 100;
            spendByMonth[month] = (spendByMonth[month] ?? 0) + own;
            final year = key ~/ 10000;
            spendByYear[year] = (spendByYear[year] ?? 0) + own;
            if (month == monthKey) {
              monthSpent += own;
              final category = t.categoryId;
              if (category != null) {
                monthByCategory[category] =
                    (monthByCategory[category] ?? 0) + own;
              }
            }
            if (inWindow) {
              spent += own;
              final category = t.categoryId ?? '';
              byCategory[category] = (byCategory[category] ?? 0) + own;
            }
          }
          if (balances.containsKey(t.accountId)) {
            balances[t.accountId] = balances[t.accountId]! - t.amountMinor;
          }
          if (inWindow && outByAccount.containsKey(t.accountId)) {
            outByAccount[t.accountId] =
                outByAccount[t.accountId]! + t.amountMinor;
          }
        case TxnType.income:
          if (!t.isSettlement) {
            final own = t.ownShareMinor;
            if (key ~/ 100 == monthKey) monthIncome += own;
            if (inWindow) income += own;
          }
          if (balances.containsKey(t.accountId)) {
            balances[t.accountId] = balances[t.accountId]! + t.amountMinor;
          }
          if (inWindow && inByAccount.containsKey(t.accountId)) {
            inByAccount[t.accountId] =
                inByAccount[t.accountId]! + t.amountMinor;
          }
        case TxnType.transfer:
          if (balances.containsKey(t.accountId)) {
            balances[t.accountId] = balances[t.accountId]! - t.amountMinor;
          }
          final to = t.toAccountId;
          if (to != null && balances.containsKey(to)) {
            balances[to] = balances[to]! + t.amountMinor;
          }
          if (inWindow) {
            if (outByAccount.containsKey(t.accountId)) {
              outByAccount[t.accountId] =
                  outByAccount[t.accountId]! + t.amountMinor;
            }
            if (to != null && inByAccount.containsKey(to)) {
              inByAccount[to] = inByAccount[to]! + t.amountMinor;
            }
          }
      }

      // Keep the four newest; a later entry wins a tie on date.
      if (recent.length < 4 || !date.isBefore(recent.last.$1)) {
        var at = recent.length;
        while (at > 0 && !date.isBefore(recent[at - 1].$1)) {
          at--;
        }
        recent.insert(at, (date, i));
        if (recent.length > 4) recent.removeLast();
      }
    }

    // -- Month ---------------------------------------------------------------
    final budget = Budgets.totalMonthlyBudgetMinor(data);
    final lastStart = DateTime(today.year, today.month - 1);
    final lastDays = DateTime(today.year, today.month, 0).day;
    final lastEnd = DateTime(
      lastStart.year,
      lastStart.month,
      today.day < lastDays ? today.day : lastDays,
    );
    final budgetRows =
        data.categories
            .map(
              (c) => CategorySpend(
                categoryId: c.id,
                name: c.name,
                budgetMinor: c.monthlyBudgetMinor,
                spentMinor: monthByCategory[c.id] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.spentMinor.compareTo(a.spentMinor));

    // -- Week ----------------------------------------------------------------
    final weekDays = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];

    // -- People and money ----------------------------------------------------
    final people = PeopleLedger.positions(data);
    final netWorth = active.fold(0, (s, a) => s + balances[a.id]!);

    return DashboardSummary(
      today: today,
      start: start,
      end: end,
      monthSpentMinor: monthSpent,
      monthIncomeMinor: monthIncome,
      monthlyBudgetMinor: budget,
      lastMonthToDateSpentMinor: _sumDays(
        spendByDay,
        DashboardFlow.dayKey(lastStart),
        DashboardFlow.dayKey(lastEnd),
      ),
      budgetRows: budgetRows
          .where((c) => c.hasBudget || c.spentMinor > 0)
          .toList(),
      weekDays: weekDays,
      weekSpentMinor: [
        for (final d in weekDays) spendByDay[DashboardFlow.dayKey(d)] ?? 0,
      ],
      weekBeforeSpentMinor: _sumDays(
        spendByDay,
        DashboardFlow.dayKey(today.subtract(const Duration(days: 13))),
        DashboardFlow.dayKey(today.subtract(const Duration(days: 7))),
      ),
      recent: [for (final (_, i) in recent) txns[i]],
      todayCount: todayCount,
      openPeople: people.where((p) => !p.isClear).toList(),
      owedToYouMinor: people.fold(0, (s, p) => s + p.owedToYouMinor),
      youOweMinor: people.fold(0, (s, p) => s + p.youOweMinor),
      spentMinor: spent,
      incomeMinor: income,
      spendByCategory: byCategory.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)),
      buckets: _buckets(
        chartLo,
        chartHi,
        chartFirstExpense,
        chartLastExpense,
        spendByDay,
        spendByMonth,
        spendByYear,
      ),
      accountFlows: [
        for (final a in active)
          AccountFlow(
            accountId: a.id,
            name: a.name,
            inMinor: inByAccount[a.id]!,
            outMinor: outByAccount[a.id]!,
          ),
      ],
      accountBalances: balances,
      netWorthMinor: netWorth,
      savings: Savings.positionFrom(data, people: people, heldMinor: netWorth),
    );
  }

  /// [DashboardFlow.spendBuckets] over the per-day, per-month and per-year
  /// totals. [firstExpense] and [lastExpense] are the first and last days in
  /// the window holding any expense (0 when none does).
  static List<SpendBucket> _buckets(
    int lo,
    int hi,
    int firstExpense,
    int lastExpense,
    Map<int, int> byDay,
    Map<int, int> byMonth,
    Map<int, int> byYear,
  ) {
    var from = _fromKey(lo);
    var to = _fromKey(hi);
    if (to.difference(from).inDays > 1200) {
      if (firstExpense == 0) {
        from = to;
      } else {
        from = _fromKey(firstExpense);
        to = _fromKey(lastExpense);
      }
    }

    final spanDays = to.difference(from).inDays + 1;
    if (spanDays <= 62) {
      final multiMonth = from.month != to.month || from.year != to.year;
      return [
        for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
          () {
            final day = DateTime(d.year, d.month, d.day);
            return SpendBucket(
              label: multiMonth ? DateFormat.Md().format(day) : '${day.day}',
              minor: byDay[DashboardFlow.dayKey(day)] ?? 0,
            );
          }(),
      ];
    }

    final spanMonths = (to.year - from.year) * 12 + (to.month - from.month) + 1;
    if (spanMonths <= 36) {
      return [
        for (var i = 0; i < spanMonths; i++)
          () {
            final m = DateTime(from.year, from.month + i);
            return SpendBucket(
              label: DateFormat.MMM().format(m),
              minor: byMonth[m.year * 100 + m.month] ?? 0,
            );
          }(),
      ];
    }
    return [
      for (var y = from.year; y <= to.year; y++)
        SpendBucket(label: '$y', minor: byYear[y] ?? 0),
    ];
  }
}
