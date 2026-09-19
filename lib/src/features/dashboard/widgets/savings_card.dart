import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Savings at a glance. The headline is the one number the owner acts on —
/// what is free to spend right now — with what they hold and their target
/// underneath it. Tapping it opens the savings screen.
class SavingsCard extends StatelessWidget {
  const SavingsCard({required this.data, required this.code, super.key});

  final AppData data;
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = Savings.position(data);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: InkWell(
          onTap: () => context.push('/savings'),
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLg),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: p.hasTarget ? 'Free to spend' : 'Holding',
                        value: Money.format(
                          p.hasTarget ? p.freeToSpendMinor : p.positionMinor,
                          code: code,
                        ),
                        valueColor: p.isDipping
                            ? AppColors.warning(brightness)
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: StatTile(
                        label: p.hasTarget ? 'Holding' : 'Target',
                        value: Money.format(
                          p.hasTarget ? p.positionMinor : 0,
                          code: code,
                        ),
                        caption: p.hasTarget
                            ? 'Target ${Money.format(p.targetMinor, code: code)}'
                            : 'Not set',
                      ),
                    ),
                  ],
                ),
                if (p.uncountedReceivablesMinor > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${Money.format(p.uncountedReceivablesMinor, code: code)} '
                    'lent out, not counted',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                SavingsProgress(position: p, code: code),
                if (p.isDipping) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SavingsDipWarning(
                    shortfallMinor: -p.freeToSpendMinor,
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
