import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/money.dart';

/// Spent / income / net for the selected window. Both figures already exclude
/// settlements, so passing money through never flatters the net.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.spentMinor,
    required this.incomeMinor,
    required this.code,
    super.key,
  });

  final int spentMinor;
  final int incomeMinor;
  final String code;

  @override
  Widget build(BuildContext context) {
    final net = incomeMinor - spentMinor;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(
                label: 'Spent',
                value: Money.format(spentMinor, code: code),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                label: 'Income',
                value: Money.format(incomeMinor, code: code),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: StatTile(
                label: 'Net',
                value: Money.format(net, code: code),
                valueColor: net < 0
                    ? AppColors.warning(Theme.of(context).brightness)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the money went: the top spending categories as ranked bars.
///
/// Every row is tappable: [onSelect] receives the category id of the row
/// (`''` for uncategorized), which the dashboard turns into the shared
/// category filter plus a jump to the activity list.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    required this.data,
    required this.start,
    required this.end,
    required this.code,
    required this.onSelect,
    super.key,
  });

  final AppData data;
  final DateTime start;
  final DateTime end;
  final String code;

  /// Called with the tapped row's category id (`''` = uncategorized).
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final sorted = DashboardFlow.spendByCategory(data, start, end);
    if (sorted.isEmpty) return const SizedBox.shrink();
    final top = sorted.take(5).toList();
    final max = top.first.value;
    final scheme = Theme.of(context).colorScheme;
    String nameFor(String id) => id.isEmpty
        ? 'Uncategorized'
        : (data.categoryById(id)?.name ?? 'Uncategorized');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top categories · tap one to see its transactions',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final c in top)
                InkWell(
                  onTap: () => onSelect(c.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                      horizontal: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                nameFor(c.key),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              flex: 2,
                              child: ValueText(
                                Money.format(c.value, code: code),
                                style: AppTextStyles.numberSmall,
                                alignment: AlignmentDirectional.centerEnd,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max == 0 ? 0 : c.value / max,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Real cash in and out of each account over the selected window —
/// settlements included, because the cash genuinely moved.
class AccountFlowCard extends StatelessWidget {
  const AccountFlowCard({required this.flows, required this.code, super.key});
  final List<AccountFlow> flows;
  final String code;

  @override
  Widget build(BuildContext context) {
    if (flows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final inColor = scheme.primary;
    final outColor = AppColors.warning(Theme.of(context).brightness);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Money in & out',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final f in flows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 3,
                        child: ValueText(
                          '+${Money.format(f.inMinor, code: code)}',
                          style: AppTextStyles.numberSmall,
                          color: inColor,
                          alignment: AlignmentDirectional.centerEnd,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 3,
                        child: ValueText(
                          '-${Money.format(f.outMinor, code: code)}',
                          style: AppTextStyles.numberSmall,
                          color: outColor,
                          alignment: AlignmentDirectional.centerEnd,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NetWorthCard extends StatelessWidget {
  const NetWorthCard({required this.data, required this.code, super.key});
  final AppData data;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Total balance',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 4,
                  child: ValueText(
                    Money.format(Balances.netWorthMinor(data), code: code),
                    style: AppTextStyles.number,
                    alignment: AlignmentDirectional.centerEnd,
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            for (final a in data.activeAccounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 4,
                      child: ValueText(
                        Money.format(
                          Balances.accountBalanceMinor(data, a.id),
                          code: code,
                        ),
                        style: AppTextStyles.numberSmall,
                        alignment: AlignmentDirectional.centerEnd,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BudgetRow extends StatelessWidget {
  const BudgetRow({required this.spend, required this.code, super.key});
  final CategorySpend spend;
  final String code;

  @override
  Widget build(BuildContext context) {
    final warn = AppColors.warning(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  spend.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 4,
                child: ValueText(
                  spend.hasBudget
                      ? '${Money.format(spend.spentMinor, code: code)} / '
                            '${Money.format(spend.budgetMinor, code: code)}'
                      : Money.format(spend.spentMinor, code: code),
                  style: AppTextStyles.numberSmall,
                  color: spend.overBudget ? warn : null,
                  alignment: AlignmentDirectional.centerEnd,
                ),
              ),
            ],
          ),
          if (spend.hasBudget) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: spend.progress,
                minHeight: 6,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                color: spend.overBudget ? warn : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
