// Benchmarks print their numbers; CI only checks loose sanity.
// ignore_for_file: avoid_print

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/activity_list.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
import 'package:budgetly/src/features/transactions/transactions_screen.dart';
import 'package:core_theme/core_theme.dart'
    show AppTheme, AppAccents, AppSpacing;
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench.dart';
import 'perf_data.dart';

/// The activity list on "All time" with 5,000 transactions: every day as an
/// eagerly built [RowGroup] versus [TxnDayCard]'s lazily built rows.
void main() {
  final today = DateTime.now();
  final data = perfData(today: DateTime(today.year, today.month, today.day));
  final start = DateTime(1970);
  final end = DateTime(2999, 12, 31);
  const filters = TxnFilters();

  test('grouping, 5,000 transactions', () async {
    report('activity grouping, ${data.txns.length} txns', {
      'filter + group + per-day totals, in build (main)': await medianMs(
        () async => _eagerGrouping(data, filters, start, end),
      ),
      'ActivityList.of, once per data/filter change': await medianMs(
        () async => ActivityList.of(data, filters, start: start, end: end),
      ),
    });
  });

  Future<(double, int)> firstFrame(
    WidgetTester tester,
    List<Widget> Function() slivers,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final watch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light, accent: AppAccents.budgetly),
        home: Scaffold(body: CustomScrollView(slivers: slivers())),
      ),
    );
    final ms = watch.elapsedMicroseconds / 1000;
    final rows = find.byType(TxnTile, skipOffstage: false).evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    return (ms, rows);
  }

  testWidgets('first frame, 5,000 transactions on All time', (tester) async {
    final eager = <double>[];
    final lazy = <double>[];
    var eagerRows = 0;
    var lazyRows = 0;
    for (var i = 0; i < 5; i++) {
      final (e, er) = await firstFrame(
        tester,
        () => _eagerSlivers(data, filters, start, end),
      );
      final (l, lr) = await firstFrame(tester, () {
        final list = ActivityList.of(data, filters, start: start, end: end);
        return [
          for (final day in list.days)
            SliverMainAxisGroup(
              slivers: [
                PinnedHeaderSliver(
                  child: TxnDayHeader(
                    day: day.day,
                    spentMinor: day.spentMinor,
                    code: 'PKR',
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                  ),
                  sliver: TxnDayCard(txns: day.txns, data: data),
                ),
              ],
            ),
        ];
      });
      eager.add(e);
      lazy.add(l);
      (eagerRows, lazyRows) = (er, lr);
    }
    double median(List<double> xs) => (xs..sort())[xs.length ~/ 2];
    report('activity first frame (build + layout + paint), 390x844', {
      'eager RowGroup per day (main)': median(eager),
      'lazy TxnDayCard': median(lazy),
    });
    report('activity rows built on the first frame', {
      'eager RowGroup per day (main)': eagerRows.toDouble(),
      'lazy TxnDayCard': lazyRows.toDouble(),
    }, unit: 'rows');
    print(
      '  days: ${ActivityList.of(data, filters, start: start, end: end).days.length}',
    );
    expect(lazyRows, lessThan(eagerRows));
  });
}

/// The list as main built it: filter, group and total the days inside
/// `build`, then one [RowGroup] holding every row of each day.
(List<Txn>, List<(DateTime, List<Txn>, int)>) _eagerGrouping(
  AppData data,
  TxnFilters filters,
  DateTime start,
  DateTime end,
) {
  final txns = filters.apply(data, start: start, end: end);
  final days = <(DateTime, List<Txn>)>[];
  for (final t in txns) {
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    if (days.isEmpty || days.last.$1 != day) days.add((day, []));
    days.last.$2.add(t);
  }
  return (
    txns,
    [
      for (final (day, items) in days)
        (
          day,
          items,
          items
              .where((t) => t.type == TxnType.expense && !t.isSettlement)
              .fold(0, (a, t) => a + t.ownShareMinor),
        ),
    ],
  );
}

List<Widget> _eagerSlivers(
  AppData data,
  TxnFilters filters,
  DateTime start,
  DateTime end,
) {
  final (_, days) = _eagerGrouping(data, filters, start, end);
  return [
    for (final (day, items, spent) in days)
      SliverMainAxisGroup(
        slivers: [
          PinnedHeaderSliver(
            child: TxnDayHeader(day: day, spentMinor: spent, code: 'PKR'),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            sliver: SliverToBoxAdapter(
              child: RowGroup(
                separatorIndent: 70,
                children: [for (final t in items) TxnTile(txn: t, data: data)],
              ),
            ),
          ),
        ],
      ),
  ];
}
