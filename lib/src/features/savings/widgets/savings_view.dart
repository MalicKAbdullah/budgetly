import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';

/// How the position sits against the target, in words.
String savingsStandingLabel(SavingsPosition p, String code) {
  if (!p.hasTarget) return 'No target set';
  if (p.freeToSpendMinor == 0) return 'Exactly on target';
  final amount = Money.format(p.freeToSpendMinor.abs(), code: code);
  return p.freeToSpendMinor > 0
      ? '$amount free to spend'
      : '$amount into your savings';
}

/// Progress toward the target, with where the owner stands underneath.
class SavingsProgress extends StatelessWidget {
  const SavingsProgress({
    required this.position,
    required this.code,
    super.key,
  });

  final SavingsPosition position;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final barColor = position.isDipping
        ? AppColors.warning(brightness)
        : AppColors.success(brightness);

    if (!position.hasTarget) {
      return Text(
        'Set a target to see how much is free to spend.',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: position.progress,
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
                savingsStandingLabel(position, code),
                style: text.bodySmall?.copyWith(color: barColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Target ${Money.format(position.targetMinor, code: code)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

/// The warning that matters: the owner is spending below their own target.
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
              'You are ${Money.format(shortfallMinor, code: code)} into your '
              'savings — you hold less than your target.',
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
