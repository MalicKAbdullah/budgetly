import 'package:core_theme/core_theme.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/reimbursements.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/dashboard/dashboard_period.dart';
import 'package:budgetly/src/features/statement/statement_pdf_service.dart';
import 'package:printing/printing.dart';

/// Selected dashboard time window (session-only; defaults to this month).
final dashboardPeriodProvider = StateProvider<DashboardPeriod>(
  (_) => DashboardPeriod.thisMonth,
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    final hasAccounts = async.valueOrNull?.accounts.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgetly'),
        actions: [
          if (hasAccounts)
            IconButton(
              tooltip: 'Export statement (PDF)',
              icon: const Icon(Icons.description_outlined),
              onPressed: () => _exportStatement(context, ref),
            ),
        ],
      ),
      floatingActionButton: hasAccounts
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/txn/new'),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load data:\n$e')),
        data: (data) => _Body(data: data),
      ),
    );
  }

  Future<void> _exportStatement(BuildContext context, WidgetRef ref) async {
    final data = ref.read(appDataProvider).valueOrNull;
    if (data == null) return;
    final period = ref.read(dashboardPeriodProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await StatementPdfService.build(
        data: data,
        period: period,
        now: DateTime.now(),
      );
      await Printing.sharePdf(bytes: bytes, filename: 'budgetly-statement.pdf');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create the statement.')),
      );
    }
  }
}

/// "Update available" card, shown when a newer GitHub release exists and the
/// user hasn't dismissed it this session.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).valueOrNull;
    final dismissed = ref.watch(updateDismissedProvider);
    if (info == null || dismissed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: UpdateBanner(
        info: info,
        onUpdate: () => ref.read(updateServiceProvider).openDownload(info),
        onDismiss: () =>
            ref.read(updateDismissedProvider.notifier).state = true,
      ),
    );
  }
}

/// "We captured N transactions — review?" banner. Shows only when the native
/// listener has queued messages the user hasn't accepted or dismissed yet.
class _CaptureBanner extends ConsumerWidget {
  const _CaptureBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingCapturesProvider).valueOrNull ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();
    final n = pending.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          leading: const Icon(Icons.mark_email_unread_outlined),
          title: Text(
            n == 1
                ? '1 captured transaction to review'
                : '$n captured transactions to review',
          ),
          subtitle: const Text(
            'From your bank/wallet alerts — accept or discard',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context
              .push('/import')
              .then((_) => ref.invalidate(pendingCapturesProvider)),
        ),
      ),
    );
  }
}

/// Fires the on-open budget notification checks exactly once per app open.
/// Renders nothing.
class _NotifyTrigger extends ConsumerStatefulWidget {
  const _NotifyTrigger({required this.data});
  final AppData data;

  @override
  ConsumerState<_NotifyTrigger> createState() => _NotifyTriggerState();
}

class _NotifyTriggerState extends ConsumerState<_NotifyTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(budgetNotifierProvider).checkOnOpen(widget.data, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Where the money went this month: the top spending categories as ranked
/// horizontal bars (all spend, budgeted or not).
class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.data,
    required this.start,
    required this.end,
    required this.code,
  });
  final AppData data;
  final DateTime start;
  final DateTime end;
  final String code;

  @override
  Widget build(BuildContext context) {
    final byCat = <String, int>{};
    for (final t in data.txns) {
      if (t.type != TxnType.expense) continue;
      if (!DashboardFlow.inRange(t.date, start, end)) continue;
      final key = t.categoryId ?? '';
      byCat[key] = (byCat[key] ?? 0) + t.ownShareMinor;
    }
    if (byCat.isEmpty) return const SizedBox.shrink();
    final sorted = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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

/// The consistent period filter chips used across the dashboard.
class _PeriodFilter extends StatelessWidget {
  const _PeriodFilter({required this.selected, required this.onSelected});
  final DashboardPeriod selected;
  final ValueChanged<DashboardPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in DashboardPeriod.values) ...[
            ChoiceChip(
              label: Text(p.label),
              selected: selected == p,
              onSelected: (_) => onSelected(p),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Money in and out of each account over the selected period.
class _AccountFlowCard extends StatelessWidget {
  const _AccountFlowCard({required this.flows, required this.code});
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

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.accounts.isEmpty) {
      return _EmptyAccounts();
    }
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final code = data.currencyCode;
    final period = ref.watch(dashboardPeriodProvider);
    final (start, end) = period.range(now);

    final spent = DashboardFlow.spentInRange(data, start, end);
    final income = DashboardFlow.incomeInRange(data, start, end);
    final buckets = DashboardFlow.spendBuckets(data, period, now);
    final flows = DashboardFlow.byAccount(
      data,
      start,
      end,
    ).where((f) => f.inMinor > 0 || f.outMinor > 0).toList();
    // Budgets stay monthly (a budget is a per-month figure).
    final budgetRows = Budgets.byCategory(
      data,
      month,
    ).where((c) => c.hasBudget || c.spentMinor > 0).toList();
    final recent = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
    final owedCount = Reimbursements.outstanding(data).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        96,
      ),
      children: [
        _NotifyTrigger(data: data),
        const _UpdateCard(),
        const _CaptureBanner(),
        _PeriodFilter(
          selected: period,
          onSelected: (p) =>
              ref.read(dashboardPeriodProvider.notifier).state = p,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SummaryCard(spentMinor: spent, incomeMinor: income, code: code),
        const SizedBox(height: AppSpacing.md),
        _SpendChart(
          buckets: buckets,
          title: '${period.label} · spending',
          code: code,
        ),
        const SizedBox(height: AppSpacing.md),
        _AccountFlowCard(flows: flows, code: code),
        _CategoryBreakdown(data: data, start: start, end: end, code: code),
        _NetWorthCard(data: data, code: code),
        if (owedCount > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.handshake_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: const Text('Owed to you'),
              subtitle: Text(
                owedCount == 1 ? '1 person owes you' : '$owedCount to collect',
              ),
              trailing: Text(
                Money.format(Reimbursements.totalOwedMinor(data), code: code),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              onTap: () => context.push('/receivables'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Budgets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/budgets'),
              child: const Text('Manage'),
            ),
          ],
        ),
        if (budgetRows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('No spending or budgets yet this month.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final c in budgetRows.take(5))
                  _BudgetRow(spend: c, code: code),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/transactions'),
              child: const Text('All'),
            ),
          ],
        ),
        if (recent.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('No transactions yet. Tap + to add one.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final t in recent.take(6)) TxnTile(txn: t, data: data),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 56),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Add your first account',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Create Cash, your bank, or a wallet to start tracking where '
              'your money goes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => context.push('/accounts'),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.spentMinor,
    required this.incomeMinor,
    required this.code,
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
            _Stat(
              label: 'Spent',
              value: Money.format(spentMinor, code: code),
            ),
            _Stat(
              label: 'Income',
              value: Money.format(incomeMinor, code: code),
            ),
            _Stat(
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
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

/// Spending chart for the selected period — thin bars (a day each for "this
/// month", a month each for the multi-month windows), peak highlighted.
class _SpendChart extends StatelessWidget {
  const _SpendChart({
    required this.buckets,
    required this.title,
    required this.code,
  });
  final List<SpendBucket> buckets;
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMinor = buckets.fold(0, (a, b) => a > b.minor ? a : b.minor);
    if (maxMinor == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < buckets.length; i++) ...[
                    Expanded(
                      child: Tooltip(
                        message:
                            '${buckets[i].label}: '
                            '${Money.format(buckets[i].minor, code: code)}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (buckets[i].minor == maxMinor)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: FittedBox(
                                  child: Text(
                                    Money.compact(maxMinor, code: code),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ),
                            Container(
                              height: buckets[i].minor == 0
                                  ? 3
                                  : 8 + 68 * (buckets[i].minor / maxMinor),
                              decoration: BoxDecoration(
                                color: buckets[i].minor == maxMinor
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.45),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i != buckets.length - 1) const SizedBox(width: 3),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  buckets.first.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  buckets.last.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard({required this.data, required this.code});
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

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.spend, required this.code});
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
                    ? '${Money.format(spend.spentMinor, code: code)} / ${Money.format(spend.budgetMinor, code: code)}'
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

/// Shared transaction row used on the dashboard and the activity list.
class TxnTile extends StatelessWidget {
  const TxnTile({required this.txn, required this.data, this.onTap, super.key});
  final Txn txn;
  final AppData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final code = data.currencyCode;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, sign) = switch (txn.type) {
      TxnType.expense => (Icons.arrow_upward, scheme.error, '-'),
      TxnType.income => (Icons.arrow_downward, scheme.primary, '+'),
      TxnType.transfer => (Icons.swap_horiz, scheme.onSurfaceVariant, ''),
    };
    final title = switch (txn.type) {
      TxnType.expense =>
        data.categoryById(txn.categoryId)?.name ?? 'Uncategorized',
      TxnType.income => txn.note.isEmpty ? 'Income' : txn.note,
      TxnType.transfer =>
        '${data.accountById(txn.accountId)?.name ?? '?'} → ${data.accountById(txn.toAccountId)?.name ?? '?'}',
    };
    final sub = [
      data.accountById(txn.accountId)?.name ?? '',
      DateFormat.MMMd().format(txn.date),
      if (txn.note.isNotEmpty && txn.type != TxnType.income) txn.note,
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '$sign${Money.format(txn.amountMinor, code: code)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
