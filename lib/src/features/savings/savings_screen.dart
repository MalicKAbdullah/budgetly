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
    final c = SuiteColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      children: [
        const PeriodFilterBar(),
        const SizedBox(height: AppSpacing.md),
        VaultCard(
          radius: AppSpacing.radiusXl,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.hasTarget ? 'Free to spend' : 'Holding',
                style: AppTextStyles.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppSpacing.smd),
              AmountText(
                p.hasTarget ? p.freeToSpendMinor : p.positionMinor,
                code: code,
                style: AppTextStyles.display,
                color: p.isDipping ? c.warning : null,
              ),
              const SizedBox(height: AppSpacing.mdl),
              SavingsProgress(position: p, code: code),
              if (p.isDipping) ...[
                const SizedBox(height: AppSpacing.smd),
                SavingsDipWarning(
                  shortfallMinor: -p.freeToSpendMinor,
                  code: code,
                ),
              ],
              const SizedBox(height: AppSpacing.mdl),
              Divider(height: 1, color: c.hairline),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Holding',
                      value: Money.format(p.positionMinor, code: code),
                      caption: p.countedReceivablesMinor > 0
                          ? 'incl. ${Money.format(p.countedReceivablesMinor, code: code)} lent'
                          : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: StatTile(
                      label: 'Target',
                      value: p.hasTarget
                          ? Money.format(p.targetMinor, code: code)
                          : 'Not set',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.smd),
        _PeriodCard(window: window, label: filter.label(now), code: code),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(
          title: 'Money lent out',
          subtitle: loans.isEmpty
              ? null
              : 'Counted ${Money.format(p.countedReceivablesMinor, code: code)} · '
                    'not counted '
                    '${Money.format(p.uncountedReceivablesMinor, code: code)}. '
                    'Switch one on when you are only passing it through '
                    'for someone.',
        ),
        if (loans.isEmpty)
          const VaultCard(
            child: AppEmptyState(
              compact: true,
              icon: Icons.handshake_outlined,
              title: 'Nothing lent out',
              message:
                  'Nothing is owed to you right now. When you front money for '
                  'someone it appears here, and you choose whether it still '
                  'counts as yours.',
            ),
          )
        else
          RowGroup(
            separatorIndent: 0,
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
    final c = SuiteColors.of(context);
    final up = window.changeMinor >= 0;
    return VaultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
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
                      '${up ? '+' : '−'}'
                      '${Money.format(window.changeMinor.abs(), code: code)}',
                  valueColor: up ? c.positive : c.warning,
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
    final c = SuiteColors.of(context);
    final counts = entry.txn.receivableCountsAsSavings;
    final who = entry.txn.counterparty.trim().isEmpty
        ? PeopleLedger.unnamedLabel
        : entry.txn.counterparty.trim();
    return Column(
      children: [
        AppListRow(
          onTap: onOpen,
          leading: IconBadge(monogram: who.characters.first.toUpperCase()),
          title: who,
          subtitle: DateFormat.yMMMd().format(entry.txn.date),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: AmountText(
              entry.outstandingMinor,
              code: code,
              style: AppTextStyles.number,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 68, right: AppSpacing.md),
          title: Text(
            'Counts as my money',
            style: AppTextStyles.bodyMedium.copyWith(color: c.textSecondary),
          ),
          value: counts,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
