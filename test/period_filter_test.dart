import 'package:core_storage/core_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/data/period_filter_store.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/models/txn.dart';

class _MemoryStorage implements ISecureStorage {
  final _map = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async =>
      _map[key] = value;

  @override
  Future<String?> read({required String key}) async => _map[key];

  @override
  Future<void> delete({required String key}) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();

  @override
  Future<Map<String, String>> readAll() async => Map.of(_map);
}

Txn _expense(String id, DateTime date, int minor) => Txn(
  id: id,
  type: TxnType.expense,
  amountMinor: minor,
  date: date,
  accountId: 'cash',
  createdAt: DateTime(2020),
);

void main() {
  final now = DateTime(2026, 7, 15);

  group('Range math', () {
    test('presets resolve to the expected windows', () {
      expect(const PeriodFilter(PeriodPreset.thisMonth).resolve(now), (
        DateTime(2026, 7),
        DateTime(2026, 7, 15),
      ));
      expect(
        const PeriodFilter(PeriodPreset.last3Months).resolve(now).$1,
        DateTime(2026, 5),
      );
      expect(
        const PeriodFilter(PeriodPreset.last6Months).resolve(now).$1,
        DateTime(2026, 2),
      );
      expect(
        const PeriodFilter(PeriodPreset.thisYear).resolve(now).$1,
        DateTime(2026),
      );
    });

    test('all time covers anything that could be stored', () {
      final (s, e) = const PeriodFilter(PeriodPreset.allTime).resolve(now);
      expect(s.isBefore(DateTime(1990)), isTrue);
      expect(e.isAfter(DateTime(2100)), isTrue);
      expect(const PeriodFilter(PeriodPreset.allTime).isAllTime, isTrue);
    });

    test('a custom range keeps both dates and orders them', () {
      final f = PeriodFilter.range(DateTime(2026, 3, 9), DateTime(2026, 1, 2));
      expect(f.preset, PeriodPreset.custom);
      expect(f.resolve(now), (DateTime(2026, 1, 2), DateTime(2026, 3, 9)));
    });

    test('a custom range missing its dates falls back to this month', () {
      const broken = PeriodFilter(PeriodPreset.custom);
      expect(broken.resolve(now).$1, DateTime(2026, 7));
    });

    test('range ends are inclusive on the day', () {
      final (s, e) = PeriodFilter.range(
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 3),
      ).resolve(now);
      expect(DashboardFlow.inRange(DateTime(2026, 7, 3, 23, 30), s, e), isTrue);
      expect(DashboardFlow.inRange(DateTime(2026, 7, 4), s, e), isFalse);
    });
  });

  group('Bucket generation', () {
    test('a single day produces one bucket', () {
      final data = AppData(txns: [_expense('a', DateTime(2026, 7, 4), 500)]);
      final buckets = DashboardFlow.spendBuckets(
        data,
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 4),
      );
      expect(buckets.length, 1);
      expect(buckets.single.minor, 500);
    });

    test('an empty single day still produces one bucket', () {
      final buckets = DashboardFlow.spendBuckets(
        const AppData(),
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 4),
      );
      expect(buckets.length, 1);
      expect(buckets.single.minor, 0);
    });

    test('a short range buckets by day', () {
      final data = AppData(txns: [_expense('a', DateTime(2026, 7, 2), 700)]);
      final buckets = DashboardFlow.spendBuckets(
        data,
        DateTime(2026, 7, 1),
        DateTime(2026, 7, 10),
      );
      expect(buckets.length, 10);
      expect(buckets[1].minor, 700);
    });

    test('a multi-month range buckets by month', () {
      final data = AppData(
        txns: [
          _expense('a', DateTime(2026, 1, 5), 100),
          _expense('b', DateTime(2026, 6, 5), 200),
        ],
      );
      final buckets = DashboardFlow.spendBuckets(
        data,
        DateTime(2026),
        DateTime(2026, 6, 30),
      );
      expect(buckets.length, 6);
      expect(buckets.first.minor, 100);
      expect(buckets.last.minor, 200);
    });

    test('a multi-year range buckets by year and never explodes', () {
      final data = AppData(
        txns: [
          _expense('a', DateTime(2019, 3, 1), 100),
          _expense('b', DateTime(2026, 3, 1), 300),
        ],
      );
      final buckets = DashboardFlow.spendBuckets(
        data,
        DateTime(1970),
        DateTime(2999, 12, 31),
      );
      expect(buckets.length, 8);
      expect(buckets.first.label, '2019');
      expect(buckets.last.label, '2026');
    });

    test('all time over an empty dataset is one harmless bucket', () {
      final (s, e) = const PeriodFilter(PeriodPreset.allTime).resolve(now);
      final buckets = DashboardFlow.spendBuckets(const AppData(), s, e);
      expect(buckets, isNotEmpty);
    });

    test('settlements never appear as spending in a bucket', () {
      final data = AppData(
        txns: [
          Txn(
            id: 's',
            type: TxnType.expense,
            amountMinor: 900,
            date: DateTime(2026, 7, 4),
            accountId: 'cash',
            settlement: true,
            createdAt: DateTime(2020),
          ),
        ],
      );
      final buckets = DashboardFlow.spendBuckets(
        data,
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 4),
      );
      expect(buckets.single.minor, 0);
    });
  });

  group('Persistence', () {
    test('a preset round-trips', () async {
      final storage = _MemoryStorage();
      await PeriodFilterStore.write(
        storage,
        const PeriodFilter(PeriodPreset.thisYear),
      );
      expect(
        await PeriodFilterStore.read(storage),
        const PeriodFilter(PeriodPreset.thisYear),
      );
    });

    test('a custom range round-trips with both dates', () async {
      final storage = _MemoryStorage();
      final f = PeriodFilter.range(DateTime(2026, 2, 3), DateTime(2026, 4, 5));
      await PeriodFilterStore.write(storage, f);
      final back = await PeriodFilterStore.read(storage);
      expect(back, f);
      expect(back.customStart, DateTime(2026, 2, 3));
      expect(back.customEnd, DateTime(2026, 4, 5));
    });

    test('switching back to a preset drops the stale custom dates', () async {
      final storage = _MemoryStorage();
      await PeriodFilterStore.write(
        storage,
        PeriodFilter.range(DateTime(2026, 2, 3), DateTime(2026, 4, 5)),
      );
      await PeriodFilterStore.write(
        storage,
        const PeriodFilter(PeriodPreset.thisMonth),
      );
      final back = await PeriodFilterStore.read(storage);
      expect(back.preset, PeriodPreset.thisMonth);
      expect(back.customStart, isNull);
    });

    test('nothing stored yet means this month', () async {
      expect(
        await PeriodFilterStore.read(_MemoryStorage()),
        const PeriodFilter.thisMonth(),
      );
    });
  });
}
