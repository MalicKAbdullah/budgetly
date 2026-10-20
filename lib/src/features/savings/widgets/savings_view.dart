import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
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
    final c = SuiteColors.of(context);
    final barColor = position.isDipping ? c.warning : c.positive;

    if (!position.hasTarget) {
      return Text(
        'Set a target to see how much is free to spend.',
        style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppProgressBar(value: position.progress, color: barColor),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                savingsStandingLabel(position, code),
                style: AppTextStyles.bodySmall.copyWith(
                  color: barColor,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Target ${Money.format(position.targetMinor, code: code)}',
              style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
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
    final c = SuiteColors.of(context);
    // Painted on the semantic warning container, so the text uses the
    // primary text colour rather than an `on*` role of a different surface.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smd),
      decoration: BoxDecoration(
        color: c.warningContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning, size: 20),
          const SizedBox(width: AppSpacing.smd),
          Expanded(
            child: Text(
              'You are ${Money.format(shortfallMinor, code: code)} into your '
              'savings — you hold less than your target.',
              style: AppTextStyles.bodySmall.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
