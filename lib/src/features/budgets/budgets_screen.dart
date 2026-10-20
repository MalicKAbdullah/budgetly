import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/widgets/progress_bar.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:uuid/uuid.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? c) async {
    final code = ref.read(appDataProvider).valueOrNull?.currencyCode ?? 'PKR';
    final result = await Navigator.of(context).push<Category>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CategoryForm(existing: c, code: code),
      ),
    );
    if (result != null) {
      await ref.read(appDataProvider.notifier).saveCategory(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final code = data?.currencyCode ?? 'PKR';
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final rows = data == null
        ? <CategorySpend>[]
        : Budgets.byCategory(data, month);
    final uncategorized = data == null
        ? 0
        : Budgets.uncategorizedSpentMinor(data, month);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Category'),
      ),
      body: rows.isEmpty && uncategorized == 0
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppEmptyState(
                  icon: Icons.donut_large_rounded,
                  title: 'No categories yet',
                  message:
                      'Add categories to track budgets — use the + button.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                112,
              ),
              children: [
                _MonthHero(
                  rows: rows,
                  uncategorizedMinor: uncategorized,
                  code: code,
                  now: now,
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(
                  title: 'Categories',
                  subtitle: 'Tap to edit · long-press to delete.',
                ),
                RowGroup(
                  children: [
                    for (final c in rows)
                      _BudgetRow(
                        spend: c,
                        code: code,
                        pace: _monthPace(now),
                        effect:
                            data?.categoryById(c.categoryId)?.savingsEffect ??
                            SavingsEffect.none,
                        onTap: () => _edit(
                          context,
                          ref,
                          data!.categories.firstWhere(
                            (x) => x.id == c.categoryId,
                          ),
                        ),
                        onLongPress: () => ref
                            .read(appDataProvider.notifier)
                            .deleteCategory(c.categoryId),
                      ),
                    if (uncategorized > 0)
                      AppListRow(
                        leading: const IconBadge(icon: Icons.help_outline),
                        title: 'Uncategorized',
                        trailing: AmountText(
                          uncategorized,
                          code: code,
                          style: AppTextStyles.number,
                          alignment: AlignmentDirectional.centerEnd,
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Share of the current month already gone: where spending "should" be.
double _monthPace(DateTime now) {
  final days = DateTime(now.year, now.month + 1, 0).day;
  return now.day / days;
}

/// The month at a glance: what has gone out against everything budgeted,
/// with the pace marker showing where an even month would be today.
class _MonthHero extends StatelessWidget {
  const _MonthHero({
    required this.rows,
    required this.uncategorizedMinor,
    required this.code,
    required this.now,
  });

  final List<CategorySpend> rows;
  final int uncategorizedMinor;
  final String code;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final budgeted = rows.where((r) => r.hasBudget);
    final budgetMinor = budgeted.fold(0, (s, r) => s + r.budgetMinor);
    final spentInBudgeted = budgeted.fold(0, (s, r) => s + r.spentMinor);
    final spentMinor =
        rows.fold(0, (s, r) => s + r.spentMinor) + uncategorizedMinor;
    final over = budgeted.where((r) => r.overBudget).length;
    final left = budgetMinor - spentInBudgeted;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;

    return VaultCard(
      radius: AppSpacing.radiusXl,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Spent · ${DateFormat.MMMM().format(now)}',
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
              ),
              DeltaBadge(
                delta: 0,
                label: daysLeft == 1 ? '1 day left' : '$daysLeft days left',
                polarity: DeltaPolarity.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.smd),
          AmountText(spentMinor, code: code, style: AppTextStyles.display),
          if (budgetMinor > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${Money.format(spentInBudgeted, code: code)} of '
              '${Money.format(budgetMinor, code: code)} budgeted',
              style: AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.mdl),
            ProgressBar(
              value: spentInBudgeted / budgetMinor,
              marker: _monthPace(now),
            ),
            const SizedBox(height: AppSpacing.mdl),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: left >= 0 ? 'Left to spend' : 'Over budget',
                    value: Money.format(left.abs(), code: code),
                    valueColor: left < 0 ? c.negative : null,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Categories over',
                    value: over == 0
                        ? 'None'
                        : over == 1
                        ? '1 category'
                        : '$over categories',
                    valueColor: over > 0 ? c.negative : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.spend,
    required this.code,
    required this.pace,
    required this.effect,
    required this.onTap,
    required this.onLongPress,
  });

  final CategorySpend spend;
  final String code;
  final double pace;
  final SavingsEffect effect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final status = !spend.hasBudget
        ? 'No budget set'
        : spend.overBudget
        ? '${Money.format(-spend.remainingMinor, code: code)} over'
        : '${Money.format(spend.remainingMinor, code: code)} left';
    final badge = switch (effect) {
      SavingsEffect.none => null,
      SavingsEffect.addsToSavings => 'Adds to savings',
      SavingsEffect.takesFromSavings => 'Takes from savings',
    };

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        flex: 5,
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
                        flex: 4,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: AmountText(
                            spend.spentMinor,
                            code: code,
                            style: AppTextStyles.number,
                            color: spend.overBudget ? c.negative : null,
                            alignment: AlignmentDirectional.centerEnd,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          badge == null ? status : '$status · $badge',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: spend.overBudget
                                ? c.negative
                                : c.textSecondary,
                          ),
                        ),
                      ),
                      if (spend.hasBudget) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'of ${Money.format(spend.budgetMinor, code: code)}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (spend.hasBudget) ...[
                    const SizedBox(height: AppSpacing.smd),
                    ProgressBar(
                      value: spend.spentMinor / spend.budgetMinor,
                      marker: pace,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({required this.code, this.existing});
  final Category? existing;
  final String code;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _name;
  late final TextEditingController _budget;
  late SavingsEffect _savingsEffect;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _savingsEffect = e?.savingsEffect ?? SavingsEffect.none;
    _name = TextEditingController(text: e?.name ?? '');
    _budget = TextEditingController(
      text: e == null || e.monthlyBudgetMinor == 0
          ? ''
          : (e.monthlyBudgetMinor / 100).toStringAsFixed(
              e.monthlyBudgetMinor % 100 == 0 ? 0 : 2,
            ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final budget = Money.parse(_budget.text) ?? 0;
    final e = widget.existing;
    final category = e == null
        ? Category(
            id: const Uuid().v4(),
            name: name,
            monthlyBudgetMinor: budget,
            savingsEffect: _savingsEffect,
            createdAt: DateTime.now(),
          )
        : e.copyWith(
            name: name,
            monthlyBudgetMinor: budget,
            savingsEffect: _savingsEffect,
          );
    Navigator.pop(context, category);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New category' : 'Edit category'),
        actions: [TextButton(onPressed: _submit, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          AppTextField(
            controller: _name,
            autofocus: true,
            label: 'Name',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _budget,
            label: 'Monthly budget (optional)',
            prefixText: Money.symbol(widget.code),
            helper: 'Leave blank to just track spending',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Savings',
            style: AppTextStyles.labelStrong.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final e in SavingsEffect.values)
                AppChip(
                  label: e.label,
                  selected: _savingsEffect == e,
                  onTap: () => setState(() => _savingsEffect = e),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Applies to every transaction in this category — including '
            'the ones you have already recorded. Money moved in or out '
            'of savings is not counted as spending or income.',
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          VaultButton(label: 'Save category', onPressed: _submit),
        ],
      ),
    );
  }
}
