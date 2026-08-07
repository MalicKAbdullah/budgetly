import 'package:core_theme/core_theme.dart';
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
          children: [
            Stat(
              label: 'Spent',
              value: Money.format(spentMinor, code: code),
            ),
            Stat(
              label: 'Income',
              value: Money.format(incomeMinor, code: code),
            ),
            Stat(
              label: 'Net',
              value: Money.format(net, code: code),
              color: net < 0
                  ? AppColors.warning(Theme.of(context).brightness)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class Stat extends StatelessWidget {
  const Stat({required this.label, required this.value, this.color, super.key});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Left-aligned like every other card row — centered columns looked off
    // against the rest of the dashboard.
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the money went: the top spending categories as ranked bars.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    required this.data,
    required this.start,
    required this.end,
    required this.code,
    super.key,
  });

  final AppData data;
  final DateTime start;
  final DateTime end;
  final String code;

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
                'Top categories',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final c in top)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nameFor(c.key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            Money.format(c.value, code: code),
                            style: Theme.of(context).textTheme.bodySmall,
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
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '+${Money.format(f.inMinor, code: code)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: inColor),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '-${Money.format(f.outMinor, code: code)}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: outColor),
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
              children: [
                Expanded(
                  child: Text(
                    'Total balance',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  Money.format(Balances.netWorthMinor(data), code: code),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            for (final a in data.activeAccounts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(a.name)),
                    Text(
                      Money.format(
                        Balances.accountBalanceMinor(data, a.id),
                        code: code,
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
              Expanded(child: Text(spend.name)),
              Text(
                spend.hasBudget
                    ? '${Money.format(spend.spentMinor, code: code)} / '
                          '${Money.format(spend.budgetMinor, code: code)}'
                    : Money.format(spend.spentMinor, code: code),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: spend.overBudget ? warn : null,
                ),
              ),
            ],
          ),
          if (spend.hasBudget) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: spend.progress,
              color: spend.overBudget ? warn : null,
            ),
          ],
        ],
      ),
    );
  }
}
