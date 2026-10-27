import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Savings at a glance. The headline is the one number the owner acts on —
/// what is free to spend right now — with what they hold and their target
/// underneath it. Tapping it opens the savings screen.
class SavingsCard extends StatelessWidget {
  const SavingsCard({required this.position, required this.code, super.key});

  final SavingsPosition position;
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final c = SuiteColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smd),
      child: VaultCard(
        onTap: () => context.push('/savings'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: Icons.savings_outlined, color: c.positive),
                const SizedBox(width: AppSpacing.smd),
                Expanded(
                  child: Text(
                    'Savings',
                    style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
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
                    valueColor: p.isDipping ? c.warning : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${Money.format(p.uncountedReceivablesMinor, code: code)} '
                'lent out, not counted',
                style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
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
    );
  }
}
