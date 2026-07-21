import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/logic/balances.dart';
import 'package:tally/src/core/logic/budgets.dart';
import 'package:tally/src/core/logic/reimbursements.dart';
import 'package:tally/src/core/models/txn.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tally')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load data:\n$e')),
        data: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});
  final AppData data;

  @override
  Widget build(BuildContext context) {
    if (data.accounts.isEmpty) {
      return _EmptyAccounts();
    }
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final code = data.currencyCode;
    final spent = Budgets.totalSpentInMonthMinor(data, month);
    final income = Budgets.totalIncomeInMonthMinor(data, month);
    final categories = Budgets.byCategory(
      data,
      month,
    ).where((c) => c.hasBudget || c.spentMinor > 0).toList();
    final recent = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          DateFormat.yMMMM().format(month),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SummaryCard(spentMinor: spent, incomeMinor: income, code: code),
        const SizedBox(height: AppSpacing.md),
        _NetWorthCard(data: data, code: code),
        if (Reimbursements.totalOwedMinor(data) > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: const Text('Owed to you'),
              trailing: Text(
                Money.format(Reimbursements.totalOwedMinor(data), code: code),
                style: const TextStyle(fontWeight: FontWeight.bold),
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
        if (categories.isEmpty)
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
                for (final c in categories.take(5))
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
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
