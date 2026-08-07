import 'package:core_storage/core_storage.dart';
import 'package:budgetly/src/core/models/period_filter.dart';

/// Persists the shared date filter in secure storage so the window the owner
/// picked is still there next launch. It is a preference, not financial data —
/// a missing or unreadable value just falls back to "This month".
abstract final class PeriodFilterStore {
  static const String presetKey = 'budgetly_period_preset';
  static const String startKey = 'budgetly_period_start';
  static const String endKey = 'budgetly_period_end';

  static Future<PeriodFilter> read(ISecureStorage storage) async =>
      PeriodFilter.fromStorage(
        preset: await storage.read(key: presetKey),
        start: await storage.read(key: startKey),
        end: await storage.read(key: endKey),
      );

  static Future<void> write(ISecureStorage storage, PeriodFilter filter) async {
    final map = filter.toStorage();
    await storage.write(key: presetKey, value: map['preset']!);
    await _writeOrDelete(storage, startKey, map['start']);
    await _writeOrDelete(storage, endKey, map['end']);
  }

  static Future<void> _writeOrDelete(
    ISecureStorage storage,
    String key,
    String? value,
  ) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}
