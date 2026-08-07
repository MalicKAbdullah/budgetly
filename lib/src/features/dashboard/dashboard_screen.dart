import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_banners.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_cards.dart';
import 'package:budgetly/src/features/dashboard/widgets/spend_chart.dart';
import 'package:budgetly/src/features/statement/statement_pdf_service.dart';
import 'package:printing/printing.dart';

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

  /// The statement covers exactly the window the shared filter is showing.
  Future<void> _exportStatement(BuildContext context, WidgetRef ref) async {
    final data = ref.read(appDataProvider).valueOrNull;
    if (data == null) return;
    final filter = ref.read(periodFilterProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await StatementPdfService.build(
        data: data,
        filter: filter,
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

class _Body extends ConsumerWidget {
  const _Body({required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.accounts.isEmpty) return const _EmptyAccounts();

    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final code = data.currencyCode;
    final filter = ref.watch(periodFilterProvider);
    final (start, end) = filter.resolve(now);

    final spent = DashboardFlow.spentInRange(data, start, end);
    final income = DashboardFlow.incomeInRange(data, start, end);
    final buckets = DashboardFlow.spendBuckets(data, start, end);
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
    final people = PeopleLedger.openPositions(data);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        96,
      ),
      children: [
        NotifyTrigger(data: data),
        const UpdateCard(),
        const CaptureBanner(),
        const PeriodFilterBar(),
        const SizedBox(height: AppSpacing.sm),
        SummaryCard(spentMinor: spent, incomeMinor: income, code: code),
        const SizedBox(height: AppSpacing.md),
        SpendChart(
          buckets: buckets,
          title: '${filter.label(now)} · spending',
          code: code,
        ),
        const SizedBox(height: AppSpacing.md),
        AccountFlowCard(flows: flows, code: code),
        CategoryBreakdown(data: data, start: start, end: end, code: code),
        NetWorthCard(data: data, code: code),
        if (people.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _PeopleCard(people: people, data: data),
        ],
        const SizedBox(height: AppSpacing.md),
        _SectionHeader(
          title: 'Budgets',
          action: 'Manage',
          onAction: () => context.go('/budgets'),
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
                  BudgetRow(spend: c, code: code),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        _SectionHeader(
          title: 'Recent',
          action: 'All',
          onAction: () => context.go('/transactions'),
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
                for (final t in recent.take(6))
                  TxnTile(
                    txn: t,
                    data: data,
                    onTap: () => context.push('/txn/${t.id}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Net split position across everyone, with a way into People / Settle up.
class _PeopleCard extends StatelessWidget {
  const _PeopleCard({required this.people, required this.data});
  final List<PersonPosition> people;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = data.currencyCode;
    final owed = PeopleLedger.totalOwedToYouMinor(data);
    final owe = PeopleLedger.totalYouOweMinor(data);
    final subtitle = [
      if (owed > 0) '${Money.format(owed, code: code)} owed to you',
      if (owe > 0) 'you owe ${Money.format(owe, code: code)}',
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.handshake_outlined, color: scheme.primary),
        ),
        title: Text(
          people.length == 1
              ? 'Settle up with ${people.first.name}'
              : 'Settle up with ${people.length} people',
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/people'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

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
