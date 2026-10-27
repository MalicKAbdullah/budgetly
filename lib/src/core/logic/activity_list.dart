import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';

/// One calendar day of the activity list.
@immutable
final class ActivityDay {
  const ActivityDay({
    required this.day,
    required this.txns,
    required this.spentMinor,
  });

  /// Midnight of the day.
  final DateTime day;

  /// The day's transactions, newest first.
  final List<Txn> txns;

  /// What the day cost the owner: own-share expense, settlements excluded.
  final int spentMinor;
}

/// The activity list for one data snapshot, filter set and date window:
/// the matching transactions grouped into days, with the totals the screen
/// shows above them.
@immutable
final class ActivityList {
  const ActivityList({
    required this.count,
    required this.days,
    required this.spentMinor,
    required this.incomeMinor,
  });

  final int count;

  /// Newest day first.
  final List<ActivityDay> days;

  /// Own-share expense, settlements excluded.
  final int spentMinor;

  /// Income received, settlements excluded.
  final int incomeMinor;

  static ActivityList of(
    AppData data,
    TxnFilters filters, {
    required DateTime start,
    required DateTime end,
  }) {
    final txns = filters.apply(data, start: start, end: end);
    final days = <ActivityDay>[];
    var spent = 0;
    var income = 0;
    var dayKey = 0;
    var dayTxns = <Txn>[];
    var daySpent = 0;
    void close() {
      if (dayTxns.isEmpty) return;
      days.add(
        ActivityDay(
          day: DateTime(dayKey ~/ 10000, dayKey ~/ 100 % 100, dayKey % 100),
          txns: dayTxns,
          spentMinor: daySpent,
        ),
      );
    }

    for (final t in txns) {
      final key = DashboardFlow.dayKey(t.date);
      if (key != dayKey) {
        close();
        dayKey = key;
        dayTxns = [];
        daySpent = 0;
      }
      dayTxns.add(t);
      if (t.isSettlement) continue;
      switch (t.type) {
        case TxnType.expense:
          spent += t.ownShareMinor;
          daySpent += t.ownShareMinor;
        case TxnType.income:
          income += t.amountMinor;
        case TxnType.transfer:
          break;
      }
    }
    close();
    return ActivityList(
      count: txns.length,
      days: days,
      spentMinor: spent,
      incomeMinor: income,
    );
  }
}
