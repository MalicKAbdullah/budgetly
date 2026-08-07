import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/money.dart';

/// Spending over the selected window — one thin bar per bucket (a day, month
/// or year depending on how wide the window is), peak highlighted.
class SpendChart extends StatelessWidget {
  const SpendChart({
    required this.buckets,
    required this.title,
    required this.code,
    super.key,
  });

  final List<SpendBucket> buckets;
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (buckets.isEmpty) return const SizedBox.shrink();
    final maxMinor = buckets.fold(0, (a, b) => a > b.minor ? a : b.minor);
    if (maxMinor == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < buckets.length; i++) ...[
                    Expanded(
                      child: Tooltip(
                        message:
                            '${buckets[i].label}: '
                            '${Money.format(buckets[i].minor, code: code)}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (buckets[i].minor == maxMinor)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: FittedBox(
                                  child: Text(
                                    Money.compact(maxMinor, code: code),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                            Container(
                              height: buckets[i].minor == 0
                                  ? 3
                                  : 8 + 68 * (buckets[i].minor / maxMinor),
                              decoration: BoxDecoration(
                                color: buckets[i].minor == maxMinor
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.45),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i != buckets.length - 1) const SizedBox(width: 3),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  buckets.first.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  buckets.last.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
