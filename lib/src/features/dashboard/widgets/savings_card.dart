import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_cards.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Savings at a glance: what has to stay put, what is actually free to spend,
/// and how that sits against the target. Tapping it opens the savings screen.
class SavingsCard extends StatelessWidget {
  const SavingsCard({required this.data, required this.code, super.key});

  final AppData data;
  final String code;

  @override
  Widget build(BuildContext context) {
    final figures = SavingsFigures.from(data);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: InkWell(
          onTap: () => context.push('/savings'),
          borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Savings',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Stat(
                      label: 'Reserved',
                      value: Money.format(figures.reservedMinor, code: code),
                    ),
                    Stat(
                      label: 'Safe to spend',
                      value: Money.format(figures.safeToSpendMinor, code: code),
                      color: figures.safeToSpendMinor < 0
                          ? AppColors.warning(brightness)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SavingsProgress(figures: figures, code: code),
                if (figures.isDipping) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SavingsDipWarning(
                    shortfallMinor: figures.shortfallMinor,
                    code: code,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
