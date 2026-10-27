import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
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
    final list = ref.watch(
      activityListProvider((filters: filters, start: start, end: end)),
    );
    final code = data.currencyCode;

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
                count: list.count,
                spent: list.spentMinor,
                income: list.incomeMinor,
                code: code,
              ),
            ],
          ),
        ),
        if (list.count == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NoMatches(
              data: data,
              filters: filters,
              onClearAll: _clearAll,
            ),
          )
        else
          for (final day in list.days)
            SliverMainAxisGroup(
              slivers: [
                PinnedHeaderSliver(
                  child: TxnDayHeader(
                    day: day.day,
                    spentMinor: day.spentMinor,
                    code: code,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.gutter,
                  ),
                  sliver: TxnDayCard(txns: day.txns, data: data),
                ),
              ],
            ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 104)),
      ],
    );
  }
}

/// One day of the activity list as a grouped card ([RowGroup]'s surface,
/// rounded hairline border and inset separators), with its rows built only
/// as they scroll into view. Each row sits on its own transparent [Material]
/// so its ink shows above the card fill; the first and last rows clip that
/// ink to the card's rounded corners.
class TxnDayCard extends StatelessWidget {
  const TxnDayCard({required this.txns, required this.data, super.key});

  /// The day's transactions, newest first.
  final List<Txn> txns;
  final AppData data;

  static const double _separatorIndent = 70;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    const corner = Radius.circular(AppSpacing.radiusLg);
    const radius = BorderRadius.all(corner);
    final last = txns.length - 1;
    return DecoratedSliver(
      decoration: ShapeDecoration(
        color: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      sliver: DecoratedSliver(
        // The border is drawn over the rows, as a [Material]'s is.
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: _ClippedOutline(
            borderRadius: radius,
            side: BorderSide(color: c.hairline),
          ),
        ),
        sliver: SliverList.builder(
          itemCount: txns.length,
          itemBuilder: (context, i) {
            final t = txns[i];
            Widget row = Material(
              type: MaterialType.transparency,
              child: TxnTile(
                txn: t,
                data: data,
                onTap: () => context.push('/txn/${t.id}'),
              ),
            );
            if (i == 0 || i == last) {
              row = ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? corner : Radius.zero,
                  bottom: i == last ? corner : Radius.zero,
                ),
                child: row,
              );
            }
            if (i == 0) return row;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Divider(height: 1, indent: _separatorIndent, color: c.hairline),
                row,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A [RoundedRectangleBorder] whose stroke is clipped to the shape's outer
/// edge, as a [Material] with an anti-aliased clip paints its border — so the
/// rounded corners match [RowGroup] pixel for pixel.
class _ClippedOutline extends RoundedRectangleBorder {
  const _ClippedOutline({super.borderRadius, super.side});

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas
      ..save()
      ..clipPath(getOuterPath(rect, textDirection: textDirection));
    super.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }
}

/// A day's heading in the activity list: the date and what the day cost.
class TxnDayHeader extends StatelessWidget {
  const TxnDayHeader({
    required this.day,
    required this.spentMinor,
    required this.code,
    super.key,
  });

  final DateTime day;

  /// What the day cost the owner, by the same rule as the totals above.
  final int spentMinor;
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
    final spent = spentMinor;
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
