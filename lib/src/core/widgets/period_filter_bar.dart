import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/providers.dart';

/// The one date-window picker, shown on every screen that shows totals.
/// Choosing here changes the window app-wide and remembers it for next launch.
class PeriodFilterBar extends ConsumerWidget {
  const PeriodFilterBar({this.padding, super.key});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(periodFilterProvider);
    final now = DateTime.now();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final p in PeriodPreset.values) ...[
            ChoiceChip(
              // The custom chip shows the chosen dates only while a custom
              // range is actually active — `filter.label` falls back to the
              // active preset's name, which otherwise renders a second chip
              // reading e.g. "This month" right beside the real one.
              label: Text(
                p == PeriodPreset.custom && filter.preset == PeriodPreset.custom
                    ? filter.label(now)
                    : p.label,
              ),
              avatar: p == PeriodPreset.custom
                  ? const Icon(Icons.date_range, size: 18)
                  : null,
              selected: filter.preset == p,
              onSelected: (_) => _select(context, ref, p, filter),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    PeriodPreset preset,
    PeriodFilter current,
  ) async {
    final controller = ref.read(periodFilterProvider.notifier);
    if (preset != PeriodPreset.custom) {
      await controller.select(PeriodFilter(preset));
      return;
    }
    final now = DateTime.now();
    final (start, end) = current.resolve(now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: current.preset == PeriodPreset.custom
          ? DateTimeRange(start: start, end: end)
          : null,
      helpText: 'Pick a date range',
    );
    if (picked == null) return;
    await controller.select(PeriodFilter.range(picked.start, picked.end));
  }
}
