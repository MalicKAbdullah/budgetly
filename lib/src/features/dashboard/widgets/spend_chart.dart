import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';

/// Spending over the selected window — one bar per bucket (a day, month or
/// year depending on how wide the window is), the peak in the accent, with
/// the average bucket above the chart.
class SpendChart extends StatelessWidget {
  const SpendChart({
    required this.buckets,
    required this.title,
    required this.unit,
    required this.code,
    super.key,
  });

  final List<SpendBucket> buckets;
  final String title;

  /// "per day", "per month": what one bar stands for, under the average.
  final String unit;
  final String code;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    final maxMinor = buckets.fold(0, (a, b) => a > b.minor ? a : b.minor);
    if (maxMinor == 0) return const SizedBox.shrink();
    final c = SuiteColors.of(context);
    final peak = buckets.indexWhere((b) => b.minor == maxMinor);
    // Dense windows (a month of days) get hairline gaps so bars stay bars.
    final gap = buckets.length > 20 ? 2.0 : 6.0;
    final caption = AppTextStyles.caption.copyWith(color: c.textTertiary);

    return VaultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AmountText(
            buckets.fold(0, (s, b) => s + b.minor) ~/ buckets.length,
            code: code,
            style: AppTextStyles.numberMedium,
          ),
          const SizedBox(height: 2),
          Text('average $unit', style: caption),
          const SizedBox(height: AppSpacing.mdl),
          SizedBox(
            height: 88,
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
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: buckets[i].minor / maxMinor),
                        duration: AppMotion.slow,
                        curve: AppMotion.emphasized,
                        builder: (context, v, _) => Container(
                          height: buckets[i].minor == 0 ? 3 : 4 + 84 * v,
                          decoration: BoxDecoration(
                            color: i == peak
                                ? c.accent
                                : c.accent.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(
                              buckets.length > 20 ? 2 : 5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i != buckets.length - 1) SizedBox(width: gap),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(buckets.first.label, style: caption),
              Text(buckets.last.label, style: caption),
            ],
          ),
        ],
      ),
    );
  }
}
