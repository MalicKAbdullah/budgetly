import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_cards.dart';
import 'package:budgetly/src/features/savings/savings_bulk_screen.dart';
import 'package:budgetly/src/features/savings/savings_target_screen.dart';
import 'package:budgetly/src/features/savings/widgets/savings_movement_tile.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Savings is a pot reserved across every account, not an account of its own.
/// This screen answers the one question: how much has to stay put, and is it
/// still there?
class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings'),
        actions: [
          IconButton(
            tooltip: 'Savings target',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => _editTarget(context, ref),
          ),
        ],
      ),
      floatingActionButton: (async.valueOrNull?.txns.isEmpty ?? true)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _bulkEarmark(context),
              icon: const Icon(Icons.checklist),
              label: const Text('Earmark transactions'),
            ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load data:\n$e')),
        data: (data) => _Body(data: data),
      ),
    );
  }

  Future<void> _editTarget(BuildContext context, WidgetRef ref) async {
    final data = ref.read(appDataProvider).valueOrNull;
    if (data == null) return;
    final target = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SavingsTargetScreen(
          initialMinor: data.savingsTargetMinor,
          code: data.currencyCode,
        ),
      ),
    );
    if (target == null) return;
    await ref.read(appDataProvider.notifier).setSavingsTarget(target);
  }

  Future<void> _bulkEarmark(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const SavingsBulkScreen()),
      );
}

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final code = data.currencyCode;
    final filter = ref.watch(periodFilterProvider);
    final (start, end) = filter.resolve(now);
    final figures = SavingsFigures.from(data);
    final savedInWindow = Savings.savedInRangeMinor(data, start, end);
    final movements = Savings.movements(data);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        96,
      ),
      children: [
        const PeriodFilterBar(),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Stat(
                      label: 'Reserved',
                      value: Money.format(figures.reservedMinor, code: code),
                    ),
                    Stat(
                      label: 'Total money',
                      value: Money.format(figures.totalMinor, code: code),
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
                const SizedBox(height: AppSpacing.md),
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
        const SizedBox(height: AppSpacing.md),
        Card(
          child: ListTile(
            leading: Icon(Icons.timeline_outlined, color: scheme.primary),
            title: Text('Saved in ${filter.label(now).toLowerCase()}'),
            subtitle: const Text(
              'Reserved minus released inside the selected window',
            ),
            trailing: Text(
              Money.format(savedInWindow, code: code),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Savings movements', style: text.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (movements.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Nothing is earmarked yet. Give a category a savings rule, set '
                'a recurring amount aside from your salary, or earmark '
                'transactions you have already recorded.',
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final m in movements)
                  SavingsMovementTile(
                    movement: m,
                    data: data,
                    onTap: () => context.push('/txn/${m.txn.id}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
