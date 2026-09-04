import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:intl/intl.dart';

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

/// Pure range roll-ups over [AppData].
///
/// "Spent" and "income" are what the owner really earned or lost: they use the
/// owner's own share, skip settlements, which only pass money through, and
/// leave out whatever part of a movement was merely earmarked as savings
/// ([Savings.spendableShareMinor]).
/// [byAccount] is deliberately different — it tracks real cash movement, so a
/// settlement still shows as money in or out of the account it touched.
abstract final class DashboardFlow {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool inRange(DateTime d, DateTime start, DateTime end) {
    final day = _day(d);
    return !day.isBefore(_day(start)) && !day.isAfter(_day(end));
  }

  static int spentInRange(AppData data, DateTime start, DateTime end) => data
      .txns
      .where(
        (t) =>
            t.type == TxnType.expense &&
            !t.isSettlement &&
            inRange(t.date, start, end),
      )
      .fold(0, (s, t) => s + Savings.spendableShareMinor(t, data));

  static int incomeInRange(AppData data, DateTime start, DateTime end) => data
      .txns
      .where(
        (t) =>
            t.type == TxnType.income &&
            !t.isSettlement &&
            inRange(t.date, start, end),
      )
      .fold(0, (s, t) => s + Savings.spendableShareMinor(t, data));

  /// Own-share expense per category id (`''` = uncategorized), biggest first.
  static List<MapEntry<String, int>> spendByCategory(
    AppData data,
    DateTime start,
    DateTime end,
  ) {
    final byCat = <String, int>{};
    for (final t in data.txns) {
      if (t.type != TxnType.expense || t.isSettlement) continue;
      if (!inRange(t.date, start, end)) continue;
      final key = t.categoryId ?? '';
      byCat[key] = (byCat[key] ?? 0) + Savings.spendableShareMinor(t, data);
    }
    return byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

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

  /// Chart bars for an arbitrary inclusive range: one per day up to two
  /// months, one per calendar month up to three years, one per year beyond.
  ///
  /// A window wider than a few years — "All time" resolves to one — is first
  /// narrowed to the days that actually hold transactions, so the chart never
  /// renders decades of empty bars. Narrower windows are charted exactly as
  /// asked, empty days and all. Always returns at least one bucket.
  static List<SpendBucket> spendBuckets(
    AppData data,
    DateTime start,
    DateTime end,
  ) {
    var from = _day(start);
    var to = _day(end);
    if (to.isBefore(from)) (from, to) = (to, from);

    if (to.difference(from).inDays > 1200) {
      final days =
          data.txns
              .where(
                (t) => t.type == TxnType.expense && inRange(t.date, from, to),
              )
              .map((t) => _day(t.date))
              .toList()
            ..sort();
      if (days.isEmpty) {
        from = to;
      } else {
        from = days.first;
        to = days.last;
      }
    }

    final spanDays = to.difference(from).inDays + 1;
    if (spanDays <= 62) return _dayBuckets(data, from, to);

    final spanMonths = (to.year - from.year) * 12 + (to.month - from.month) + 1;
    if (spanMonths <= 36) return _monthBuckets(data, from, spanMonths);
    return _yearBuckets(data, from.year, to.year);
  }

  static List<SpendBucket> _dayBuckets(
    AppData data,
    DateTime from,
    DateTime to,
  ) {
    final multiMonth = from.month != to.month || from.year != to.year;
    final buckets = <SpendBucket>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      final day = _day(d);
      final total = data.txns
          .where(
            (t) =>
                t.type == TxnType.expense &&
                !t.isSettlement &&
                _day(t.date) == day,
          )
          .fold(0, (s, t) => s + Savings.spendableShareMinor(t, data));
      buckets.add(
        SpendBucket(
          label: multiMonth ? DateFormat.Md().format(day) : '${day.day}',
          minor: total,
        ),
      );
    }
    return buckets;
  }

  static List<SpendBucket> _monthBuckets(
    AppData data,
    DateTime from,
    int count,
  ) {
    final buckets = <SpendBucket>[];
    for (var i = 0; i < count; i++) {
      final m = DateTime(from.year, from.month + i);
      final total = data.txns
          .where(
            (t) =>
                t.type == TxnType.expense &&
                !t.isSettlement &&
                t.date.year == m.year &&
                t.date.month == m.month,
          )
          .fold(0, (s, t) => s + Savings.spendableShareMinor(t, data));
      buckets.add(SpendBucket(label: DateFormat.MMM().format(m), minor: total));
    }
    return buckets;
  }

  static List<SpendBucket> _yearBuckets(
    AppData data,
    int fromYear,
    int toYear,
  ) {
    final buckets = <SpendBucket>[];
    for (var y = fromYear; y <= toYear; y++) {
      final total = data.txns
          .where(
            (t) =>
                t.type == TxnType.expense &&
                !t.isSettlement &&
                t.date.year == y,
          )
          .fold(0, (s, t) => s + Savings.spendableShareMinor(t, data));
      buckets.add(SpendBucket(label: '$y', minor: total));
    }
    return buckets;
  }
}
