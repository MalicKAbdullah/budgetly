import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';

/// The headline savings numbers, ready for both the dashboard card and the
/// savings screen so the two can never drift apart.
@immutable
final class SavingsFigures {
  const SavingsFigures({
    required this.reservedMinor,
    required this.totalMinor,
    required this.safeToSpendMinor,
    required this.targetMinor,
    required this.varianceMinor,
    required this.isDipping,
  });

  final int reservedMinor;
  final int totalMinor;
  final int safeToSpendMinor;
  final int targetMinor;
  final int varianceMinor;
  /// Every figure comes from [Savings], so the card, the screen and the tests
  /// all read the same resolver.
  factory SavingsFigures.from(AppData data) => SavingsFigures(
    reservedMinor: Savings.reservedMinor(data),
    totalMinor: Savings.totalMinor(data),
    safeToSpendMinor: Savings.safeToSpendMinor(data),
    targetMinor: data.savingsTargetMinor,
    varianceMinor: Savings.varianceMinor(data),
    isDipping: Savings.isDipping(data),
  );

  final bool isDipping;

  bool get hasTarget => targetMinor > 0;

  /// How much of the reserved pot is no longer covered by real money.
  int get shortfallMinor => reservedMinor - totalMinor;

  /// 0..1 for the progress bar; 0 when no target is set.
  double get progress {
    if (targetMinor <= 0) return 0;
    return (reservedMinor / targetMinor).clamp(0.0, 1.0).toDouble();
  }
}

/// The "+/-": how the reserved pot sits against the target, in words.
String savingsVarianceLabel(SavingsFigures f, String code) {
  if (!f.hasTarget) return 'No target set';
  if (f.varianceMinor == 0) return 'Exactly on target';
  final amount = Money.format(f.varianceMinor.abs(), code: code);
  return f.varianceMinor > 0
      ? '+$amount ahead of target'
      : '-$amount short of target';
}

/// Progress toward the target with the variance spelled out underneath.
class SavingsProgress extends StatelessWidget {
  const SavingsProgress({
    required this.figures,
    required this.code,
    super.key,
  });

  final SavingsFigures figures;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final ahead = figures.varianceMinor >= 0;
    final barColor = ahead
        ? AppColors.success(brightness)
        : AppColors.warning(brightness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (figures.hasTarget) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: figures.progress,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              color: barColor,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  savingsVarianceLabel(figures, code),
                  style: text.bodySmall?.copyWith(color: barColor),
                ),
              ),
              Text(
                'Target ${Money.format(figures.targetMinor, code: code)}',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ] else
          Text(
            'Set a target to see how far ahead or short you are.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// The warning that matters: money the owner had reserved has been spent.
class SavingsDipWarning extends StatelessWidget {
  const SavingsDipWarning({
    required this.shortfallMinor,
    required this.code,
    super.key,
  });

  final int shortfallMinor;
  final String code;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // Painted on the semantic warning container, so the text uses the theme's
    // primary text colour for that brightness rather than an `on*` role that
    // belongs to a different surface.
    final background = brightness == Brightness.dark
        ? AppColors.warningContainerDark
        : AppColors.warningContainerLight;
    final foreground = AppColors.textPrimary(brightness);
    final accent = AppColors.warning(brightness);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: accent, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'You are into your savings by '
              '${Money.format(shortfallMinor, code: code)} — you have less '
              'money than you have reserved.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
