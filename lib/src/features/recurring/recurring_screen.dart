import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/providers.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final code = data?.currencyCode ?? 'PKR';
    final templates = data?.recurringTemplates ?? const <RecurringTemplate>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            onPressed: () => context.push('/recurring/new'),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add recurring',
          ),
        ],
      ),
      body: templates.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: AppEmptyState(
                  icon: Icons.event_repeat_rounded,
                  title: 'Nothing recurring',
                  message:
                      'Add repeating transactions like salary, rent, or '
                      'subscriptions. They post automatically when due.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                AppSpacing.xxl,
              ),
              children: [
                _MonthlyCommitments(templates: templates, code: code),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(
                  title: 'Schedules',
                  subtitle: 'Tap to edit · long-press to delete.',
                ),
                RowGroup(
                  children: [
                    for (final t in templates)
                      _TemplateRow(
                        template: t,
                        title: t.note.isNotEmpty
                            ? t.note
                            : data!.categoryById(t.categoryId)?.name ??
                                  t.type.label,
                        code: code,
                        onToggle: (v) => ref
                            .read(appDataProvider.notifier)
                            .setRecurringActive(t.id, v),
                        onTap: () => context.push('/recurring/${t.id}'),
                        onLongPress: () => ref
                            .read(appDataProvider.notifier)
                            .deleteRecurring(t.id),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// What the active schedules add up to over a month, so the owner sees the
/// fixed part of their budget at a glance.
class _MonthlyCommitments extends StatelessWidget {
  const _MonthlyCommitments({required this.templates, required this.code});

  final List<RecurringTemplate> templates;
  final String code;

  static int _perMonth(RecurringTemplate t) => switch (t.interval) {
    RecurringInterval.weekly => t.amountMinor * 52 ~/ 12,
    RecurringInterval.monthly => t.amountMinor,
    RecurringInterval.yearly => t.amountMinor ~/ 12,
  };

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final active = templates.where((t) => t.active);
    final out = active
        .where((t) => t.type == TxnType.expense)
        .fold(0, (s, t) => s + _perMonth(t));
    final inc = active
        .where((t) => t.type == TxnType.income)
        .fold(0, (s, t) => s + _perMonth(t));
    final paused = templates.length - active.length;
    return VaultCard(
      radius: AppSpacing.radiusXl,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fixed spending · per month',
            style: AppTextStyles.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.smd),
          AmountText(out, code: code, style: AppTextStyles.display),
          const SizedBox(height: AppSpacing.mdl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatTile(
                  label: 'Recurring income',
                  value: Money.format(inc, code: code),
                ),
              ),
              Expanded(
                child: StatTile(
                  label: 'Active',
                  value: '${active.length}',
                  caption: paused > 0 ? '$paused paused' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.title,
    required this.code,
    required this.onToggle,
    required this.onTap,
    required this.onLongPress,
  });

  final RecurringTemplate template;
  final String title;
  final String code;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final t = template;
    final badge = switch (t.type) {
      TxnType.expense => IconBadge(
        icon: CategoryVisual.icon(title),
        color: t.active ? CategoryVisual.color(context, title) : null,
      ),
      TxnType.income => IconBadge(
        icon: Icons.south_west_rounded,
        color: t.active ? c.positive : null,
      ),
      TxnType.transfer => const IconBadge(icon: Icons.swap_horiz_rounded),
    };
    final secondary = AppTextStyles.bodySmall.copyWith(color: c.textSecondary);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.smd,
          AppSpacing.sm,
          AppSpacing.smd,
        ),
        child: Row(
          children: [
            badge,
            const SizedBox(width: AppSpacing.smd + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: t.active ? c.textPrimary : c.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AmountText(
                    t.type == TxnType.expense ? -t.amountMinor : t.amountMinor,
                    code: code,
                    style: AppTextStyles.numberSmall,
                    tone: t.type == TxnType.income && t.active
                        ? MoneyTone.signed
                        : MoneyTone.neutral,
                    showPlus: t.type == TxnType.income,
                    color: t.active ? null : c.textTertiary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.interval.label} · '
                    '${t.active ? 'next ${DateFormat.yMMMd().format(t.nextRunDate)}' : 'paused'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
                ],
              ),
            ),
            Switch(value: t.active, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}
