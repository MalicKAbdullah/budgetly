import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/state/category_filter.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_banners.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_cards.dart';
import 'package:budgetly/src/features/dashboard/widgets/savings_card.dart';
import 'package:budgetly/src/features/dashboard/widgets/home_hero.dart';
import 'package:budgetly/src/features/dashboard/widgets/spend_chart.dart';
import 'package:budgetly/src/features/people/people_screen.dart';
import 'package:budgetly/src/features/statement/statement_pdf_service.dart';
import 'package:printing/printing.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    final hasAccounts = async.valueOrNull?.accounts.isNotEmpty ?? false;
    return Scaffold(
      floatingActionButton: hasAccounts
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/txn/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Transaction'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load your data',
          message: '$e',
        ),
        data: (data) =>
            _Body(data: data, onExport: () => _exportStatement(context, ref)),
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
  const _Body({required this.data, required this.onExport});
  final AppData data;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.accounts.isEmpty) return const _EmptyAccounts();

    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final code = data.currencyCode;
    final filter = ref.watch(periodFilterProvider);
    final summary = ref.watch(
      dashboardSummaryProvider(DateTime(now.year, now.month, now.day)),
    );
    final (start, end) = (summary.start, summary.end);
    // Budgets stay monthly (a budget is a per-month figure).
    final budgetRows = summary.budgetRows;
    final recent = summary.recent;
    final todayCount = summary.todayCount;
    final people = summary.openPeople;
    final c = SuiteColors.of(context);

    return SafeArea(
      bottom: false,
      child: Center(
        // Wide screens keep the phone's reading measure instead of stretching
        // every card edge to edge.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.mdl,
              AppSpacing.gutter,
              112,
            ),
            children: [
              // The first screen answers the daily questions in order: what
              // needs a decision (captured alerts), what can be spent, which
              // budgets are slipping, who owes whom. Where the money went and
              // the account detail follow below.
              //
              // Banners and cards that can vanish carry their own bottom gap,
              // so a hidden one leaves no hole.
              NotifyTrigger(data: data),
              _Header(now: now, onExport: onExport),
              const SizedBox(height: AppSpacing.lg),
              const CaptureBanner(),
              const UpdateCard(),
              MonthHeroCard(
                summary: summary,
                code: code,
                onTap: () => context.go('/budgets'),
              ),
              const SizedBox(height: AppSpacing.smd),
              BudgetPair(
                rows: budgetRows,
                now: now,
                code: code,
                onTap: () => context.go('/budgets'),
              ),
              if (people.isNotEmpty) ...[
                _PeopleSection(
                  people: people,
                  owedToYouMinor: summary.owedToYouMinor,
                  youOweMinor: summary.youOweMinor,
                  code: code,
                ),
                const SizedBox(height: AppSpacing.smd),
              ],
              const SizedBox(height: AppSpacing.smd),
              SectionHeader(
                title: 'Recent',
                subtitle: todayCount == 0
                    ? 'Nothing yet today'
                    : todayCount == 1
                    ? '1 transaction today'
                    : '$todayCount transactions today',
                actionLabel: 'See all',
                onAction: () => context.go('/transactions'),
              ),
              recent.isEmpty
                  ? const VaultCard(
                      child: AppEmptyState(
                        compact: true,
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions yet',
                        message: 'Tap Transaction to add your first one.',
                      ),
                    )
                  : RowGroup(
                      children: [
                        for (final t in recent)
                          TxnTile(
                            txn: t,
                            data: data,
                            onTap: () => context.push('/txn/${t.id}'),
                          ),
                      ],
                    ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                title: 'Where it went',
                subtitle: filter.label(now),
              ),
              const PeriodFilterBar(),
              const SizedBox(height: AppSpacing.smd),
              SummaryCard(
                spentMinor: summary.spentMinor,
                incomeMinor: summary.incomeMinor,
                code: code,
                onTap: () => context.go('/transactions'),
              ),
              const SizedBox(height: AppSpacing.smd),
              CategoryBreakdown(
                data: data,
                sorted: summary.spendByCategory,
                code: code,
                onSelect: (categoryId) {
                  // One tap answers "what did I spend this on": narrow every
                  // screen to that category, then land on the list.
                  ref.read(categoryFilterProvider.notifier).select(categoryId);
                  context.go('/transactions');
                },
              ),
              const SizedBox(height: AppSpacing.smd),
              SpendChart(
                buckets: summary.buckets,
                title: 'Spending by ${_bucketNoun(start, end)}',
                unit: 'per ${_bucketNoun(start, end)}',
                code: code,
                onTap: () => context.go('/transactions'),
              ),
              const SizedBox(height: AppSpacing.smd),
              WeekCard(
                summary: summary,
                code: code,
                onTap: () => context.go('/transactions'),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                title: 'Money',
                actionLabel: 'Accounts',
                onAction: () => context.push('/accounts'),
              ),
              SavingsCard(position: summary.savings, code: code),
              AccountsCard(
                data: data,
                flows: summary.accountFlows,
                balances: summary.accountBalances,
                netWorthMinor: summary.netWorthMinor,
                code: code,
                onTap: () => context.push('/accounts'),
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                title: 'Budgets',
                subtitle: DateFormat.MMMM().format(month),
                actionLabel: 'Manage',
                onAction: () => context.go('/budgets'),
              ),
              budgetRows.isEmpty
                  ? VaultCard(
                      onTap: () => context.go('/budgets'),
                      child: const AppEmptyState(
                        compact: true,
                        icon: Icons.donut_large_rounded,
                        title: 'No budgets yet',
                        message: 'Set a monthly budget to see what is left.',
                      ),
                    )
                  : RowGroup(
                      children: [
                        for (final row in budgetRows.take(5))
                          InkWell(
                            onTap: () => context.go('/budgets'),
                            child: BudgetRow(spend: row, code: code),
                          ),
                      ],
                    ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Text(
                  'Everything stays on this phone.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What one bar of the spending chart stands for.
  static String _bucketNoun(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    if (days <= 62) return 'day';
    if (days <= 36 * 31) return 'month';
    return 'year';
  }
}

/// Date eyebrow, greeting and the statement export.
class _Header extends StatelessWidget {
  const _Header({required this.now, required this.onExport});
  final DateTime now;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM').format(now),
                style: AppTextStyles.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text(
                  greeting,
                  style: AppTextStyles.h2.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Export statement (PDF)',
          style: IconButton.styleFrom(
            backgroundColor: c.surfaceAlt,
            foregroundColor: c.textPrimary,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          onPressed: onExport,
        ),
      ],
    );
  }
}

/// Who owes the owner and whom the owner owes, biggest balance first, each
/// row opening that person's ledger to settle up.
class _PeopleSection extends StatelessWidget {
  const _PeopleSection({
    required this.people,
    required this.owedToYouMinor,
    required this.youOweMinor,
    required this.code,
  });
  final List<PersonPosition> people;
  final int owedToYouMinor;
  final int youOweMinor;
  final String code;

  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final owed = owedToYouMinor;
    final owe = youOweMinor;
    final sorted = [...people]
      ..sort((a, b) => b.netMinor.abs().compareTo(a.netMinor.abs()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Settle up',
          subtitle: [
            if (owed > 0) '${Money.format(owed, code: code)} owed to you',
            if (owe > 0) 'you owe ${Money.format(owe, code: code)}',
          ].join(' · '),
          actionLabel: people.length > _shown
              ? 'All ${people.length}'
              : 'People',
          onAction: () => context.push('/people'),
        ),
        RowGroup(
          children: [
            for (final p in sorted.take(_shown))
              PersonRow(
                position: p,
                code: code,
                onTap: () =>
                    context.push('/people/${PeopleLedger.routeKeyFor(p.key)}'),
              ),
          ],
        ),
      ],
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts();

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Spacer(),
            const SuiteAppIcon(app: SuiteApp.budgetly, size: 72),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Welcome to Budgetly',
              textAlign: TextAlign.center,
              style: AppTextStyles.h1.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                'Add Cash, your bank or a wallet to start tracking where your '
                'money goes. Everything stays on this phone.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: c.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            VaultButton(
              label: 'Add account',
              icon: Icons.add_rounded,
              onPressed: () => context.push('/accounts'),
            ),
            const Spacer(),
            const SuiteEndorsement(),
          ],
        ),
      ),
    );
  }
}
