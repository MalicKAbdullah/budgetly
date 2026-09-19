import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/features/savings/savings_target_screen.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Savings is a line the owner draws, not a pot they fill. This screen answers
/// one question — how much is free to spend — and lets them decide which money
/// they have lent out still counts as theirs.
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
    final p = Savings.position(data);
    final window = Savings.period(data, start, end);
    final loans = Savings.openLoans(data);
    final text = Theme.of(context).textTheme;
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
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        label: 'Holding',
                        value: Money.format(p.positionMinor, code: code),
                        caption: p.countedReceivablesMinor > 0
                            ? 'incl. ${Money.format(p.countedReceivablesMinor, code: code)} lent'
                            : null,
                      ),
                    ),
                  ],
                ),
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
        ),
        const SizedBox(height: AppSpacing.md),
        _PeriodCard(window: window, label: filter.label(now), code: code),
        const SizedBox(height: AppSpacing.md),
        SectionHeader(title: 'Money lent out'),
        if (loans.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Nothing is owed to you right now. When you front money for '
                'someone it appears here, and you choose whether it still '
                'counts as yours.',
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Counted ${Money.format(p.countedReceivablesMinor, code: code)} · '
              'not counted '
              '${Money.format(p.uncountedReceivablesMinor, code: code)}',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final loan in loans)
                  _LoanRow(
                    entry: loan,
                    code: code,
                    onChanged: (v) => ref
                        .read(appDataProvider.notifier)
                        .setReceivableCountsAsSavings(loan.txn.id, v),
                    onOpen: () => context.push('/txn/${loan.txn.id}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Carry-over, movement and closing position for the selected window. This is
/// what makes money saved in an earlier month visible: it arrives as
/// "carried in" rather than falling outside the filter.
class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.window,
    required this.label,
    required this.code,
  });

  final SavingsPeriod window;
  final String label;
  final String code;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final up = window.changeMinor >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Carried in',
                    value: Money.format(window.carriedInMinor, code: code),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    label: 'Change',
                    value:
                        '${up ? '+' : '-'}'
                        '${Money.format(window.changeMinor.abs(), code: code)}',
                    valueColor: up
                        ? AppColors.success(brightness)
                        : AppColors.warning(brightness),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: StatTile(
                    label: 'At end',
                    value: Money.format(window.closingMinor, code: code),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One open loan, with the switch that decides whether it still counts as the
/// owner's money.
class _LoanRow extends StatelessWidget {
  const _LoanRow({
    required this.entry,
    required this.code,
    required this.onChanged,
    required this.onOpen,
  });

  final DebtEntry entry;
  final String code;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final counts = entry.txn.receivableCountsAsSavings;
    final who = entry.txn.counterparty.trim().isEmpty
        ? PeopleLedger.unnamedLabel
        : entry.txn.counterparty.trim();
    return Column(
      children: [
        ListTile(
          onTap: onOpen,
          title: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            DateFormat.yMMMd().format(entry.txn.date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: MoneyTrailing(
            amount: Money.format(entry.outstandingMinor, code: code),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.sm,
          ),
          title: const Text('Counts as my money'),
          subtitle: const Text(
            'On when you are only passing it through for someone',
          ),
          value: counts,
          onChanged: onChanged,
        ),
        const Divider(height: 1),
      ],
    );
  }
}
