import 'package:flutter/foundation.dart' show immutable;
import 'package:intl/intl.dart';

/// The app-wide time window presets. [custom] carries two explicit dates.
enum PeriodPreset {
  thisMonth('This month'),
  last3Months('Last 3 months'),
  last6Months('Last 6 months'),
  thisYear('This year'),
  allTime('All time'),
  custom('Custom range');

  const PeriodPreset(this.label);
  final String label;

  static PeriodPreset parse(String? raw) => PeriodPreset.values.firstWhere(
    (p) => p.name == raw,
    orElse: () => PeriodPreset.thisMonth,
  );
}

/// The one date filter shared by the dashboard, the activity list and the
/// statement export — chosen once, remembered across launches.
///
/// A filter is a preset plus, for [PeriodPreset.custom], an explicit inclusive
/// start and end day. [range] resolves it against the current wall clock.
@immutable
final class PeriodFilter {
  const PeriodFilter(this.preset, {this.customStart, this.customEnd});

  const PeriodFilter.thisMonth() : this(PeriodPreset.thisMonth);

  factory PeriodFilter.range(DateTime start, DateTime end) {
    final a = _dayStart(start);
    final b = _dayStart(end);
    final ordered = a.isAfter(b) ? (b, a) : (a, b);
    return PeriodFilter(
      PeriodPreset.custom,
      customStart: ordered.$1,
      customEnd: ordered.$2,
    );
  }

  /// Restores a persisted filter. Anything missing or unparsable falls back to
  /// "This month" rather than failing — the filter is a preference, not data.
  factory PeriodFilter.fromStorage({
    String? preset,
    String? start,
    String? end,
  }) {
    final p = PeriodPreset.parse(preset);
    if (p != PeriodPreset.custom) return PeriodFilter(p);
    final s = start == null ? null : DateTime.tryParse(start);
    final e = end == null ? null : DateTime.tryParse(end);
    if (s == null || e == null) return const PeriodFilter.thisMonth();
    return PeriodFilter.range(s, e);
  }

  final PeriodPreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  bool get isAllTime => preset == PeriodPreset.allTime;

  /// Custom without both dates is not usable — treated as "This month".
  bool get _customIsComplete =>
      preset == PeriodPreset.custom && customStart != null && customEnd != null;

  /// Inclusive `[start, end]` day range, resolved against [now].
  /// "All time" returns a window wide enough to hold any stored date.
  (DateTime, DateTime) resolve(DateTime now) {
    final today = _dayStart(now);
    return switch (preset) {
      PeriodPreset.thisMonth => (DateTime(now.year, now.month), today),
      PeriodPreset.last3Months => (DateTime(now.year, now.month - 2), today),
      PeriodPreset.last6Months => (DateTime(now.year, now.month - 5), today),
      PeriodPreset.thisYear => (DateTime(now.year), today),
      PeriodPreset.allTime => (DateTime(1970), DateTime(2999, 12, 31)),
      PeriodPreset.custom =>
        _customIsComplete
            ? (customStart!, customEnd!)
            : (DateTime(now.year, now.month), today),
    };
  }

  /// What the chips and the statement header show.
  String label(DateTime now) {
    if (!_customIsComplete) return preset.label;
    final s = customStart!;
    final e = customEnd!;
    final sameYear = s.year == e.year;
    final f = sameYear ? DateFormat.MMMd() : DateFormat.yMMMd();
    return '${f.format(s)} – ${DateFormat.yMMMd().format(e)}';
  }

  Map<String, String?> toStorage() => {
    'preset': preset.name,
    'start': customStart?.toIso8601String(),
    'end': customEnd?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is PeriodFilter &&
      other.preset == preset &&
      other.customStart == customStart &&
      other.customEnd == customEnd;

  @override
  int get hashCode => Object.hash(preset, customStart, customEnd);

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
}
