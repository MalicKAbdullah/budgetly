import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/activity_list.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'perf/perf_data.dart';

/// [ActivityList] against the straightforward grouping the activity screen
/// is defined by, on random 5,000-transaction vaults.
void main() {
  final today = DateTime(2026, 10, 27);

  void expectSame(AppData data, TxnFilters filters, DateTime s, DateTime e) {
    final list = ActivityList.of(data, filters, start: s, end: e);

    final txns = filters.apply(data, start: s, end: e);
    final days = <(DateTime, List<Txn>)>[];
    for (final t in txns) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      if (days.isEmpty || days.last.$1 != day) days.add((day, []));
      days.last.$2.add(t);
    }
    int spentOf(Iterable<Txn> ts) => ts
        .where((t) => t.type == TxnType.expense && !t.isSettlement)
        .fold(0, (a, t) => a + t.ownShareMinor);

    expect(list.count, txns.length);
    expect(list.spentMinor, spentOf(txns));
    expect(
      list.incomeMinor,
      txns
          .where((t) => t.type == TxnType.income && !t.isSettlement)
          .fold(0, (a, t) => a + t.amountMinor),
    );
    expect(list.days.map((d) => d.day), days.map((d) => d.$1));
    for (var i = 0; i < days.length; i++) {
      expect(list.days[i].txns, days[i].$2);
      expect(list.days[i].spentMinor, spentOf(days[i].$2));
    }
  }

  final windows = [
    for (final f in [
      const PeriodFilter.thisMonth(),
      const PeriodFilter(PeriodPreset.last6Months),
      const PeriodFilter(PeriodPreset.allTime),
      PeriodFilter.range(DateTime(2025, 3, 1), DateTime(2025, 3, 31)),
      PeriodFilter.range(DateTime(2010, 1, 1), DateTime(2011, 1, 1)),
    ])
      f.resolve(today),
  ];
  const filterSets = [
    TxnFilters(),
    TxnFilters(type: TxnType.expense),
    TxnFilters(type: TxnType.income),
    TxnFilters(accountId: 'a2'),
    TxnFilters(categoryId: 'c3'),
    TxnFilters(categoryId: ''),
    TxnFilters(search: 'split'),
    TxnFilters(search: 'nothing matches this'),
    TxnFilters(type: TxnType.transfer, accountId: 'a0'),
  ];

  for (final seed in [1, 2]) {
    test('seed $seed: days, rows and totals match the plain grouping', () {
      final data = perfData(today: today, seed: seed);
      for (final (s, e) in windows) {
        for (final filters in filterSets) {
          expectSame(data, filters, s, e);
        }
      }
    });
  }

  test('an empty vault has no days', () {
    final list = ActivityList.of(
      const AppData(),
      const TxnFilters(),
      start: DateTime(1970),
      end: DateTime(2999),
    );
    expect(list.days, isEmpty);
    expect((list.count, list.spentMinor, list.incomeMinor), (0, 0, 0));
  });

  test('filters with the same values are equal, so the list is reused', () {
    expect(
      const TxnFilters(type: TxnType.expense, search: 'x'),
      TxnFilters(type: TxnType.expense, search: ['x'].join()),
    );
    expect(const TxnFilters(), isNot(const TxnFilters(categoryId: '')));
  });
}
