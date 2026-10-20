import 'dart:math' as math;

import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/widgets/progress_bar.dart';

/// The month at a glance: what is left of the budget (or what has gone, with
/// no budget set), how that compares with the same point last month, and the
/// month's shape as a line.
///
/// Budgets are per month, so this card always describes the calendar month,
/// whatever window the period chips select further down.
class MonthHeroCard extends StatelessWidget {
  const MonthHeroCard({
    required this.data,
    required this.now,
    this.onTap,
    super.key,
  });

  final AppData data;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final code = data.currencyCode;
    final month = DateTime(now.year, now.month);
    final monthName = DateFormat.MMMM().format(month);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysLeft = daysInMonth - now.day + 1;

    final spent = Budgets.totalSpentInMonthMinor(data, month);
    final income = Budgets.totalIncomeInMonthMinor(data, month);
    final budget = Budgets.totalMonthlyBudgetMinor(data);
    final hasBudget = budget > 0;
    final left = budget - spent;

    // Month-to-date against the same days of last month, so a half-gone
    // month is never compared with a whole one.
    final lastStart = DateTime(now.year, now.month - 1);
    final lastDays = DateTime(now.year, now.month, 0).day;
    final lastEnd = DateTime(
      lastStart.year,
      lastStart.month,
      math.min(now.day, lastDays),
    );
    final lastSpent = DashboardFlow.spentInRange(data, lastStart, lastEnd);
    final delta = lastSpent == 0 ? null : (spent - lastSpent) * 100 / lastSpent;

    // Cumulative spend per day so far; with a budget the line is what was
    // left at the end of each day.
    var running = 0;
    final trend = <double>[
      for (var d = 1; d <= now.day; d++)
        () {
          final day = DateTime(now.year, now.month, d);
          running += DashboardFlow.spentInRange(data, day, day);
          return (hasBudget ? budget - running : running) / 100;
        }(),
    ];

    String fmt(int minor) => Money.format(minor, code: code);
    final perDay = left > 0 ? left ~/ daysLeft : 0;
    final saved = income > 0 ? ((income - spent) * 100 / income).round() : null;

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
        color: hasBudget && left < 0 ? SuiteColors.of(context).negative : null,
      ),
      delta: delta == null
          ? null
          : DeltaBadge(delta: delta, polarity: DeltaPolarity.upIsBad),
      deltaCaption: delta == null
          ? null
          : delta <= 0
          ? 'less spent than this time last month'
          : 'more spent than this time last month',
      trend: trend.length < 2 ? null : trend,
      footer: hasBudget
          ? [
              StatTile(label: 'Budget', value: fmt(budget)),
              StatTile(label: 'Spent', value: fmt(spent)),
              StatTile(label: 'Per day', value: fmt(perDay)),
            ]
          : [
              StatTile(label: 'Income', value: fmt(income)),
              StatTile(label: 'Net', value: fmt(income - spent)),
              StatTile(label: 'Saved', value: saved == null ? '—' : '$saved%'),
            ],
    );
  }
}

/// The two budgets closest to their limit, side by side, each with a tick
/// where spending would be if it were on pace for the month. A budget spent
/// to the exact amount is a fixed bill already paid, not one to watch, so it
/// only shows when nothing else is budgeted.
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

  @override
  Widget build(BuildContext context) {
    final all = rows.where((r) => r.hasBudget).toList();
    final open = all.where((r) => r.spentMinor != r.budgetMinor).toList();
    final budgeted = (open.isEmpty ? all : open)
      ..sort(
        (a, b) => (b.spentMinor / b.budgetMinor).compareTo(
          a.spentMinor / a.budgetMinor,
        ),
      );
    if (budgeted.isEmpty) return const SizedBox.shrink();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final pace = now.day / daysInMonth;

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
      caption: 'of ${Money.format(s.budgetMinor, code: code)}',
      visual: ProgressBar(value: s.spentMinor / s.budgetMinor, marker: pace),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.smd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: card(budgeted[0])),
          const SizedBox(width: AppSpacing.smd),
          Expanded(
            child: budgeted.length > 1
                ? card(budgeted[1])
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// The last seven days as bars, today highlighted, against the seven before.
class WeekCard extends StatelessWidget {
  const WeekCard({required this.data, required this.now, super.key});

  final AppData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final values = [
      for (final d in days) DashboardFlow.spentInRange(data, d, d),
    ];
    final total = values.fold(0, (a, b) => a + b);
    final before = DashboardFlow.spentInRange(
      data,
      today.subtract(const Duration(days: 13)),
      today.subtract(const Duration(days: 7)),
    );
    final delta = before == 0 ? null : (total - before) * 100 / before;

    return VaultCard(
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
          AmountText(
            total,
            code: data.currencyCode,
            style: AppTextStyles.numberLarge,
          ),
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
