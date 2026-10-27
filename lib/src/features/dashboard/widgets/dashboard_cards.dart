import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/widgets/progress_bar.dart';

/// Net, spent and income for the selected window. Both figures already
/// exclude settlements, so passing money through never flatters the net.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.spentMinor,
    required this.incomeMinor,
    required this.code,
    this.onTap,
    super.key,
  });

  final int spentMinor;
  final int incomeMinor;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final net = incomeMinor - spentMinor;
    return VaultCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Net leads: it is the one figure that says whether the period is
          // going well; spent and income are its explanation.
          Text(
            'Net',
            style: AppTextStyles.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CountUp(
            minor: net,
            builder: (v) => AmountText(
              v,
              code: code,
              style: AppTextStyles.numberLarge,
              tone: MoneyTone.signed,
              showPlus: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (incomeMinor > 0 || spentMinor > 0) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedBar(
                values: [
                  spentMinor.toDouble(),
                  (incomeMinor - spentMinor).clamp(0, incomeMinor).toDouble(),
                ],
                colors: [c.accent, c.surfaceAlt],
                height: 8,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatTile(
                  label: 'Spent',
                  dotColor: c.accent,
                  value: Money.format(spentMinor, code: code),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: StatTile(
                  label: 'Income',
                  dotColor: c.border,
                  value: Money.format(incomeMinor, code: code),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Glides a figure to its new value when the period changes, so the owner
/// sees the direction of the change. The first build shows the value as-is:
/// counting up from zero on every app open would be noise, not information.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.minor, required this.builder});

  final int minor;
  final Widget Function(int minor) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: minor, end: minor),
      duration: AppMotion.slow,
      curve: AppMotion.standard,
      // Whole units while in flight, so passing cents don't flicker.
      builder: (_, v, _) => builder(v == minor ? v : v ~/ 100 * 100),
    );
  }
}

/// Where the money went: the top spending categories as a donut with a
/// ranked legend.
///
/// Every legend row is tappable: [onSelect] receives the category id of the
/// row (`''` for uncategorized), which the dashboard turns into the shared
/// category filter plus a jump to the activity list.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({
    required this.data,
    required this.sorted,
    required this.code,
    required this.onSelect,
    super.key,
  });

  final AppData data;

  /// Own-share spend per category id, biggest first
  /// ([DashboardFlow.spendByCategory]).
  final List<MapEntry<String, int>> sorted;
  final String code;

  /// Called with the tapped row's category id (`''` = uncategorized).
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    final c = SuiteColors.of(context);
    final total = sorted.fold(0, (s, e) => s + e.value);
    if (total == 0) return const SizedBox.shrink();
    final top = sorted.take(5).toList();
    final rest = total - top.fold(0, (s, e) => s + e.value);
    String nameFor(String id) => id.isEmpty
        ? 'Uncategorized'
        : (data.categoryById(id)?.name ?? 'Uncategorized');
    final colors = [
      for (var i = 0; i < top.length; i++) c.chart[i % c.chart.length],
    ];

    return VaultCard(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.mdl, 0, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdl),
            child: Row(
              children: [
                DonutChart(
                  size: 112,
                  thickness: 14,
                  segments: [
                    for (var i = 0; i < top.length; i++)
                      DonutSegment(
                        value: top[i].value.toDouble(),
                        color: colors[i],
                      ),
                    if (rest > 0)
                      DonutSegment(value: rest.toDouble(), color: c.border),
                  ],
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(top.first.value * 100 / total).round()}%',
                        style: AppTextStyles.numberMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        'top',
                        style: AppTextStyles.caption.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.mdl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The period's total sits on the summary card just
                      // above, so this side names the spread instead.
                      Text(
                        'Spent across',
                        style: AppTextStyles.label.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        sorted.length == 1
                            ? '1 category'
                            : '${sorted.length} categories',
                        style: AppTextStyles.h4.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tap one to see its transactions',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.smd),
          for (var i = 0; i < top.length; i++)
            InkWell(
              onTap: () => onSelect(top[i].key),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdl,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smd),
                      Expanded(
                        flex: 3,
                        child: Text(
                          nameFor(top[i].key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: ValueText(
                          Money.format(top[i].value, code: code),
                          style: AppTextStyles.numberSmall,
                          alignment: AlignmentDirectional.centerEnd,
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(top[i].value * 100 / total).round()}%',
                          textAlign: TextAlign.end,
                          style: AppTextStyles.numberSmall.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Every account's balance under the total, with the real cash in and out of
/// each over the selected window — settlements included, because the cash
/// genuinely moved.
class AccountsCard extends StatelessWidget {
  const AccountsCard({
    required this.data,
    required this.flows,
    required this.balances,
    required this.netWorthMinor,
    required this.code,
    this.onTap,
    super.key,
  });

  final AppData data;
  final List<AccountFlow> flows;

  /// Current balance per account id.
  final Map<String, int> balances;
  final int netWorthMinor;
  final String code;
  final VoidCallback? onTap;

  static IconData iconFor(AccountType type) => switch (type) {
    AccountType.cash => Icons.payments_outlined,
    AccountType.bank => Icons.account_balance_outlined,
    AccountType.wallet => Icons.account_balance_wallet_outlined,
    AccountType.card => Icons.credit_card_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final flowById = {for (final f in flows) f.accountId: f};
    return VaultCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.mdl,
              AppSpacing.mdl,
              AppSpacing.mdl,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total balance',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                AmountText(
                  netWorthMinor,
                  code: code,
                  style: AppTextStyles.numberLarge,
                ),
              ],
            ),
          ),
          for (final a in data.activeAccounts) ...[
            Divider(height: 1, indent: 72, color: c.hairline),
            AppListRow(
              leading: IconBadge(icon: iconFor(a.type)),
              title: a.name,
              subtitle: _flowLine(flowById[a.id]),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: AmountText(
                  balances[a.id]!,
                  code: code,
                  style: AppTextStyles.number,
                  alignment: AlignmentDirectional.centerEnd,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _flowLine(AccountFlow? f) {
    if (f == null || (f.inMinor == 0 && f.outMinor == 0)) return 'No movement';
    return [
      if (f.inMinor > 0) 'In ${Money.format(f.inMinor, code: code)}',
      if (f.outMinor > 0) 'Out ${Money.format(f.outMinor, code: code)}',
    ].join(' · ');
  }
}

/// One category's month: spent against its budget, with what is left.
class BudgetRow extends StatelessWidget {
  const BudgetRow({required this.spend, required this.code, super.key});
  final CategorySpend spend;
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final left = spend.remainingMinor;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.smd + 2,
      ),
      child: Row(
        children: [
          IconBadge(
            icon: CategoryVisual.icon(spend.name),
            color: CategoryVisual.color(context, spend.name),
          ),
          const SizedBox(width: AppSpacing.smd + 2),
          Expanded(
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
                        style: AppTextStyles.body.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 3,
                      child: ValueText(
                        Money.format(spend.spentMinor, code: code),
                        style: AppTextStyles.number,
                        alignment: AlignmentDirectional.centerEnd,
                      ),
                    ),
                  ],
                ),
                if (spend.hasBudget) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ProgressBar(value: spend.spentMinor / spend.budgetMinor),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    spend.overBudget
                        ? '${Money.format(-left, code: code)} over · '
                              'budget ${Money.format(spend.budgetMinor, code: code)}'
                        : '${Money.format(left, code: code)} left of '
                              '${Money.format(spend.budgetMinor, code: code)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: spend.overBudget ? c.negative : c.textSecondary,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    'No budget set',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
