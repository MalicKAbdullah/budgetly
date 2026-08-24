import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/state/category_filter.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
import 'package:budgetly/src/features/transactions/txn_filter_bar.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  TxnType? _type;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The type/account/search pickers live on this screen; the category comes
  /// from the app-wide filter, so a tap on the dashboard breakdown lands here
  /// already narrowed.
  TxnFilters get _filters => TxnFilters(
    type: _type,
    accountId: _accountId,
    categoryId: ref.watch(categoryFilterProvider),
    search: _search.text,
  );

  void _clearAll() {
    ref.read(categoryFilterProvider.notifier).clear();
    _search.clear();
    setState(() {
      _type = null;
      _accountId = null;
    });
  }

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
    // list always describe the same slice of time. Everything else narrows on
    // top of it.
    final (start, end) = ref
        .watch(periodFilterProvider)
        .resolve(DateTime.now());
    final filters = _filters;
    final filtered = filters.apply(data, start: start, end: end);

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
        const SizedBox(height: AppSpacing.xs),
        TxnFilterBar(
          data: data,
          filters: filters,
          searchController: _search,
          onType: (t) => setState(() => _type = t),
          onAccount: (a) => setState(() => _accountId = a),
          onCategory: (c) =>
              ref.read(categoryFilterProvider.notifier).select(c),
          onClearAll: _clearAll,
        ),
        _TotalsLine(
          count: filtered.length,
          spent: spent,
          income: received,
          code: code,
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? _NoMatches(data: data, filters: filters, onClearAll: _clearAll)
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

class _TotalsLine extends StatelessWidget {
  const _TotalsLine({
    required this.count,
    required this.spent,
    required this.income,
    required this.code,
  });

  final int count;
  final int spent;
  final int income;
  final String code;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
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
              '$count ${count == 1 ? 'transaction' : 'transactions'}',
              style: style,
            ),
          ),
          Text(
            'Spent ${Money.format(spent, code: code)}'
            ' · Income ${Money.format(income, code: code)}',
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Empty result: says which filters are hiding everything and offers one tap
/// to drop them, so the owner never sees a bare blank list.
class _NoMatches extends StatelessWidget {
  const _NoMatches({
    required this.data,
    required this.filters,
    required this.onClearAll,
  });

  final AppData data;
  final TxnFilters filters;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final reasons = [
      if (filters.categoryId != null)
        'category "${categoryFilterLabel(data, filters.categoryId!)}"',
      if (filters.type != null) filters.type!.label.toLowerCase(),
      if (filters.accountId != null)
        data.accountById(filters.accountId)?.name ?? 'that account',
      if (filters.search.trim().isNotEmpty) '"${filters.search.trim()}"',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Nothing to show here',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              reasons.isEmpty
                  ? 'No transactions fall inside the selected dates.'
                  : 'Nothing in the selected dates matches '
                        '${reasons.join(' + ')}.',
              textAlign: TextAlign.center,
            ),
            if (filters.isActive) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
