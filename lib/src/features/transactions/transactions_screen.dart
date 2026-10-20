import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
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
              icon: const Icon(Icons.add_rounded),
              label: const Text('Transaction'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => data.txns.isEmpty
            ? _NoTransactions(hasAccounts: hasAccounts)
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: AppSpacing.sm),
              const PeriodFilterBar(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              ),
              const SizedBox(height: AppSpacing.md),
              _Totals(
                count: filtered.length,
                spent: spent,
                income: received,
                code: code,
              ),
            ],
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NoMatches(
              data: data,
              filters: filters,
              onClearAll: _clearAll,
            ),
          )
        else
          ..._daySlivers(context, filtered, data, code),
        const SliverPadding(padding: EdgeInsets.only(bottom: 104)),
      ],
    );
  }
}

/// The filtered list split into days, newest first: each day is one grouped
/// card under a header that stays pinned while its day scrolls by and shows
/// what that day cost. [txns] is already sorted newest first by
/// [TxnFilters.apply].
List<Widget> _daySlivers(
  BuildContext context,
  List<Txn> txns,
  AppData data,
  String code,
) {
  final days = <(DateTime, List<Txn>)>[];
  for (final t in txns) {
    final day = DateTime(t.date.year, t.date.month, t.date.day);
    if (days.isEmpty || days.last.$1 != day) days.add((day, []));
    days.last.$2.add(t);
  }
  return [
    for (final (day, items) in days)
      SliverMainAxisGroup(
        slivers: [
          PinnedHeaderSliver(
            child: _DayHeader(day: day, txns: items, code: code),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            sliver: SliverToBoxAdapter(
              child: RowGroup(
                separatorIndent: 70,
                children: [
                  for (final t in items)
                    TxnTile(
                      txn: t,
                      data: data,
                      onTap: () => context.push('/txn/${t.id}'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
  ];
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.txns, required this.code});

  final DateTime day;
  final List<Txn> txns;
  final String code;

  String _label(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return day.year == now.year
        ? DateFormat('EEE, d MMM').format(day)
        : DateFormat('EEE, d MMM y').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    // Same "what did this cost me" rule as the totals above the list.
    final spent = txns
        .where((t) => t.type == TxnType.expense && !t.isSettlement)
        .fold(0, (a, t) => a + t.ownShareMinor);
    return Container(
      color: c.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter + AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.gutter + AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _label(DateTime.now()),
              style: AppTextStyles.labelStrong.copyWith(color: c.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (spent > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: AmountText(
                -spent,
                code: code,
                style: AppTextStyles.numberSmall.copyWith(
                  color: c.textSecondary,
                ),
                color: c.textSecondary,
                alignment: AlignmentDirectional.centerEnd,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How many transactions the filters let through and what they add up to.
class _Totals extends StatelessWidget {
  const _Totals({
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
    final c = SuiteColors.of(context);
    Widget figure(String label, Widget value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          value,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: VaultCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          AppSpacing.md,
          AppSpacing.cardPadding,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count ${count == 1 ? 'transaction' : 'transactions'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelStrong.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppSpacing.smd),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                figure(
                  'Spent',
                  AmountText(
                    spent,
                    code: code,
                    style: AppTextStyles.numberMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                figure(
                  'Income',
                  AmountText(
                    income,
                    code: code,
                    style: AppTextStyles.numberMedium,
                    tone: MoneyTone.signed,
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

/// First run: nothing recorded yet. Points at the one step that unblocks the
/// screen — an account if there is none (the editor needs one), else a first
/// transaction.
class _NoTransactions extends StatelessWidget {
  const _NoTransactions({required this.hasAccounts});

  final bool hasAccounts;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: AppEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No transactions yet',
          message: hasAccounts
              ? 'Everything you spend and receive will be listed here, '
                    'grouped by day.'
              : 'Add an account first — every transaction belongs to one.',
          action: hasAccounts
              ? VaultButton(
                  label: 'Add transaction',
                  icon: Icons.add_rounded,
                  isFullWidth: false,
                  onPressed: () => context.push('/txn/new'),
                )
              : VaultButton(
                  label: 'Add account',
                  icon: Icons.account_balance_wallet_outlined,
                  isFullWidth: false,
                  onPressed: () => context.push('/accounts'),
                ),
        ),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing to show here',
        message: reasons.isEmpty
            ? 'No transactions fall inside the selected dates.'
            : 'Nothing in the selected dates matches '
                  '${reasons.join(' + ')}.',
        action: filters.isActive
            ? VaultButton(
                label: 'Clear filters',
                icon: Icons.filter_alt_off_outlined,
                isFullWidth: false,
                onPressed: onClearAll,
              )
            : null,
      ),
    );
  }
}
