import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/dashboard_summary.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/widgets/progress_bar.dart';

/// The month at a glance, answering "how much can I still spend": what is
/// left of the budget and what that allows per day for the rest of the month
/// (or, with no budget set, what has gone and how that compares with last
/// month).
///
/// Budgets are per month, so this card always describes the calendar month,
/// whatever window the period chips select further down.
class MonthHeroCard extends StatelessWidget {
  const MonthHeroCard({
    required this.summary,
    required this.code,
    this.onTap,
    super.key,
  });

  final DashboardSummary summary;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final now = summary.today;
    final month = DateTime(now.year, now.month);
    final monthName = DateFormat.MMMM().format(month);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    // Today counts: money left today is still spendable today.
    final daysLeft = daysInMonth - now.day + 1;

    final spent = summary.monthSpentMinor;
    final income = summary.monthIncomeMinor;
    final budget = summary.monthlyBudgetMinor;
    final hasBudget = budget > 0;
    final left = budget - spent;

    final lastSpent = summary.lastMonthToDateSpentMinor;
    final delta = lastSpent == 0 ? null : (spent - lastSpent) * 100 / lastSpent;

    String fmt(int minor) => Money.format(minor, code: code);
    final saved = income > 0 ? ((income - spent) * 100 / income).round() : null;

    final Widget? lead;
    final String? leadCaption;
    if (!hasBudget) {
      lead = delta == null
          ? null
          : DeltaBadge(delta: delta, polarity: DeltaPolarity.upIsBad);
      leadCaption = delta == null
          ? null
          : delta <= 0
          ? 'less spent than this time last month'
          : 'more spent than this time last month';
    } else if (left > 0) {
      lead = AmountText(
        left ~/ daysLeft,
        code: code,
        style: AppTextStyles.numberMedium,
        color: c.accent,
      );
      leadCaption = daysLeft == 1
          ? 'to spend today'
          : 'a day to stay on budget';
    } else {
      lead = null;
      leadCaption = left == 0
          ? 'Budget used up for $monthName'
          : 'Over budget for $monthName';
    }

    return HeroMetricCard(
      onTap: onTap,
      label: hasBudget ? 'Left to spend · $monthName' : 'Spent · $monthName',
      trailing: DeltaBadge(
        delta: 0,
        label: daysLeft == 1 ? 'Last day' : '$daysLeft days left',
        polarity: DeltaPolarity.neutral,
      ),
      value: AmountText(
        hasBudget ? left : spent,
        code: code,
        style: AppTextStyles.hero,
        color: hasBudget && left < 0 ? c.negative : null,
      ),
      delta: lead,
      deltaCaption: leadCaption,
      footer: hasBudget
          ? [
              StatTile(label: 'Spent', value: fmt(spent)),
              StatTile(label: 'Budget', value: fmt(budget)),
              StatTile(
                label: 'vs last month',
                value: delta == null
                    ? '—'
                    : '${delta > 0 ? '+' : '−'}${delta.abs().round()}%',
                valueColor: delta == null || delta.round() == 0
                    ? null
                    : delta > 0
                    ? c.negative
                    : c.positive,
              ),
            ]
          : [
              StatTile(label: 'Income', value: fmt(income)),
              StatTile(label: 'Net', value: fmt(income - spent)),
              StatTile(label: 'Saved', value: saved == null ? '—' : '$saved%'),
            ],
    );
  }
}

/// The budgets that need attention this month, worst first, as two cards side
/// by side with a tick where spending would be if it were on pace. Renders
/// nothing while every budget is comfortably on track.
class BudgetPair extends StatelessWidget {
  const BudgetPair({
    required this.rows,
    required this.now,
    required this.code,
    required this.onTap,
    super.key,
  });

  final List<CategorySpend> rows;
  final DateTime now;
  final String code;
  final VoidCallback onTap;

  /// Budgets over their limit, at 80 % or more of it, or at least half spent
  /// and running ahead of the month's pace — worst first. A budget spent to
  /// the exact amount is a fixed bill already paid, not one to watch.
  static List<CategorySpend> atRisk(List<CategorySpend> rows, DateTime now) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final pace = now.day / daysInMonth;
    double used(CategorySpend s) => s.spentMinor / s.budgetMinor;
    return rows.where((s) {
      if (!s.hasBudget || s.spentMinor == s.budgetMinor) return false;
      final u = used(s);
      return u >= 0.8 || (u >= 0.5 && u > pace);
    }).toList()..sort((a, b) => used(b).compareTo(used(a)));
  }

  @override
  Widget build(BuildContext context) {
    final watch = atRisk(rows, now);
    if (watch.isEmpty) return const SizedBox.shrink();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final pace = now.day / daysInMonth;
    final over = watch.where((s) => s.overBudget).length;
    final close = watch.length - over;

    Widget card(CategorySpend s) => MetricCard(
      label: s.name,
      icon: CategoryVisual.icon(s.name),
      iconColor: CategoryVisual.color(context, s.name),
      onTap: onTap,
      value: AmountText(
        s.spentMinor,
        code: code,
        style: AppTextStyles.numberMedium,
      ),
      caption: s.overBudget
          ? '${Money.format(-s.remainingMinor, code: code)} over'
          : '${Money.format(s.remainingMinor, code: code)} left',
      visual: ProgressBar(value: s.spentMinor / s.budgetMinor, marker: pace),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Budgets to watch',
            subtitle: [
              if (over > 0) '$over over',
              if (close > 0) '$close close to the limit',
            ].join(' · '),
            actionLabel: 'All',
            onAction: onTap,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: card(watch[0])),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: watch.length > 1
                    ? card(watch[1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The last seven days as bars, today highlighted, against the seven before.
class WeekCard extends StatelessWidget {
  const WeekCard({
    required this.summary,
    required this.code,
    this.onTap,
    super.key,
  });

  final DashboardSummary summary;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final days = summary.weekDays;
    final values = summary.weekSpentMinor;
    final total = values.fold(0, (a, b) => a + b);
    final before = summary.weekBeforeSpentMinor;
    final delta = before == 0 ? null : (total - before) * 100 / before;

    return VaultCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last 7 days',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
              ),
              if (delta != null)
                DeltaBadge(
                  delta: delta,
                  polarity: DeltaPolarity.upIsBad,
                  subtle: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AmountText(total, code: code, style: AppTextStyles.numberLarge),
          const SizedBox(height: AppSpacing.mdl),
          Semantics(
            label: 'Spending per day, last seven days',
            child: MiniBarChart(
              values: [for (final v in values) v / 100],
              labels: [for (final d in days) DateFormat.E().format(d)[0]],
              highlightIndex: 6,
            ),
          ),
        ],
      ),
    );
  }
}
