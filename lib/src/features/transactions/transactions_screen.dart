import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TxnType? _type;
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appDataProvider);
    final hasAccounts = async.valueOrNull?.accounts.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      floatingActionButton: hasAccounts
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/txn/new'),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => data.txns.isEmpty
            ? const Center(
                child: Text('No transactions yet — add one with the + button.'),
              )
            : _list(data),
      ),
    );
  }

  Widget _list(AppData data) {
    // The window comes from the app-wide filter, so the dashboard and this
    // list always describe the same slice of time.
    final (start, end) = ref
        .watch(periodFilterProvider)
        .resolve(DateTime.now());
    final filtered = data.txns.where((t) {
      if (!DashboardFlow.inRange(t.date, start, end)) return false;
      if (_type != null && t.type != _type) return false;
      if (_accountId != null &&
          t.accountId != _accountId &&
          t.toAccountId != _accountId) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    final code = data.currencyCode;
    // Header totals answer "what did this cost me", so they use own share and
    // skip settlements — the same rule as the dashboard.
    final spent = filtered
        .where((t) => t.type == TxnType.expense && !t.isSettlement)
        .fold(0, (a, t) => a + t.ownShareMinor);
    final received = filtered
        .where((t) => t.type == TxnType.income && !t.isSettlement)
        .fold(0, (a, t) => a + t.amountMinor);

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.sm),
          child: PeriodFilterBar(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _TypeAndAccountFilters(
          accounts: data.accounts,
          type: _type,
          accountId: _accountId,
          onType: (t) => setState(() => _type = t),
          onAccount: (a) => setState(() => _accountId = a),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${filtered.length} '
                  '${filtered.length == 1 ? 'transaction' : 'transactions'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                'Spent ${Money.format(spent, code: code)}'
                ' · Income ${Money.format(received, code: code)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('Nothing matches these filters.'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => TxnTile(
                    txn: filtered[i],
                    data: data,
                    onTap: () => context.push('/txn/${filtered[i].id}'),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TypeAndAccountFilters extends StatelessWidget {
  const _TypeAndAccountFilters({
    required this.accounts,
    required this.type,
    required this.accountId,
    required this.onType,
    required this.onAccount,
  });

  final List<Account> accounts;
  final TxnType? type;
  final String? accountId;
  final ValueChanged<TxnType?> onType;
  final ValueChanged<String?> onAccount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          for (final (label, t) in [
            ('All', null),
            ('Expenses', TxnType.expense),
            ('Income', TxnType.income),
            ('Transfers', TxnType.transfer),
          ]) ...[
            ChoiceChip(
              label: Text(label),
              selected: type == t,
              onSelected: (_) => onType(t),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          const SizedBox(width: AppSpacing.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: accountId,
              hint: const Text('All accounts'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All accounts'),
                ),
                for (final a in accounts)
                  DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
              ],
              onChanged: onAccount,
            ),
          ),
        ],
      ),
    );
  }
}
