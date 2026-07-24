import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// The dashboard/statement time window.
enum DashboardPeriod { thisMonth, last3Months, last6Months }

extension DashboardPeriodX on DashboardPeriod {
  String get label => switch (this) {
    DashboardPeriod.thisMonth => 'This month',
    DashboardPeriod.last3Months => '3 months',
    DashboardPeriod.last6Months => '6 months',
  };

  /// Inclusive [start, end] range ending at [now]. "This month" starts on the
  /// 1st; the N-month windows start on the 1st of the (N-1)-months-ago month.
  (DateTime, DateTime) range(DateTime now) {
    final start = switch (this) {
      DashboardPeriod.thisMonth => DateTime(now.year, now.month),
      DashboardPeriod.last3Months => DateTime(now.year, now.month - 2),
      DashboardPeriod.last6Months => DateTime(now.year, now.month - 5),
    };
    return (start, now);
  }
}

/// Money in and out of a single account over a window.
class AccountFlow {
  const AccountFlow({
    required this.accountId,
    required this.name,
    required this.inMinor,
    required this.outMinor,
  });

  final String accountId;
  final String name;
  final int inMinor;
  final int outMinor;

  int get netMinor => inMinor - outMinor;
}

/// One bar of the spending chart.
class SpendBucket {
  const SpendBucket({required this.label, required this.minor});
  final String label;
  final int minor;
}

/// Pure range roll-ups over [AppData]. "Spent"/"income" use the owner's own
/// share and exclude transfers (matching the budget view); per-account flow
/// tracks real cash movement (full amounts, transfers counted both sides).
abstract final class DashboardFlow {
  static bool inRange(DateTime d, DateTime start, DateTime end) {
    final day = DateTime(d.year, d.month, d.day);
    final from = DateTime(start.year, start.month, start.day);
    return !day.isBefore(from) && !d.isAfter(end);
  }

  static int spentInRange(AppData data, DateTime start, DateTime end) => data
      .txns
      .where((t) => t.type == TxnType.expense && inRange(t.date, start, end))
      .fold(0, (s, t) => s + t.ownShareMinor);

  static int incomeInRange(AppData data, DateTime start, DateTime end) => data
      .txns
      .where((t) => t.type == TxnType.income && inRange(t.date, start, end))
      .fold(0, (s, t) => s + t.amountMinor);

  static List<AccountFlow> byAccount(
    AppData data,
    DateTime start,
    DateTime end,
  ) {
    final inByAcct = <String, int>{};
    final outByAcct = <String, int>{};
    for (final a in data.activeAccounts) {
      inByAcct[a.id] = 0;
      outByAcct[a.id] = 0;
    }
    for (final t in data.txns) {
      if (!inRange(t.date, start, end)) continue;
      switch (t.type) {
        case TxnType.income:
          if (inByAcct.containsKey(t.accountId)) {
            inByAcct[t.accountId] = inByAcct[t.accountId]! + t.amountMinor;
          }
        case TxnType.expense:
          if (outByAcct.containsKey(t.accountId)) {
            outByAcct[t.accountId] = outByAcct[t.accountId]! + t.amountMinor;
          }
        case TxnType.transfer:
          if (outByAcct.containsKey(t.accountId)) {
            outByAcct[t.accountId] = outByAcct[t.accountId]! + t.amountMinor;
          }
          final to = t.toAccountId;
          if (to != null && inByAcct.containsKey(to)) {
            inByAcct[to] = inByAcct[to]! + t.amountMinor;
          }
      }
    }
    return [
      for (final a in data.activeAccounts)
        AccountFlow(
          accountId: a.id,
          name: a.name,
          inMinor: inByAcct[a.id] ?? 0,
          outMinor: outByAcct[a.id] ?? 0,
        ),
    ];
  }

  /// Spending buckets for the chart: one per day for "this month", one per
  /// calendar month for the multi-month windows.
  static List<SpendBucket> spendBuckets(
    AppData data,
    DashboardPeriod period,
    DateTime now,
  ) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    if (period == DashboardPeriod.thisMonth) {
      final buckets = <SpendBucket>[];
      for (var day = 1; day <= now.day; day++) {
        final d = DateTime(now.year, now.month, day);
        final total = data.txns
            .where(
              (t) =>
                  t.type == TxnType.expense &&
                  t.date.year == d.year &&
                  t.date.month == d.month &&
                  t.date.day == d.day,
            )
            .fold(0, (s, t) => s + t.ownShareMinor);
        buckets.add(SpendBucket(label: '$day', minor: total));
      }
      return buckets;
    }
    final months = period == DashboardPeriod.last3Months ? 3 : 6;
    final buckets = <SpendBucket>[];
    for (var i = months - 1; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      final total = data.txns
          .where(
            (t) =>
                t.type == TxnType.expense &&
                t.date.year == m.year &&
                t.date.month == m.month,
          )
          .fold(0, (s, t) => s + t.ownShareMinor);
      buckets.add(SpendBucket(label: monthNames[m.month - 1], minor: total));
    }
    return buckets;
  }
}
