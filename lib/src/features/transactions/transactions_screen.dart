import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/dashboard/dashboard_screen.dart'
    show TxnTile;
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  /// null = all time; otherwise the first day of the shown month.
  DateTime? _month = DateTime(DateTime.now().year, DateTime.now().month);
  TxnType? _type;
  String? _accountId;

  void _shiftMonth(int delta) {
    final m = _month ?? DateTime(DateTime.now().year, DateTime.now().month);
    setState(() => _month = DateTime(m.year, m.month + delta));
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
        data: (data) {
          if (data.txns.isEmpty) {
            return const Center(
              child: Text('No transactions yet — add one with the + button.'),
            );
          }
          final txns = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
          final filtered = txns.where((t) {
            if (_month != null) {
              if (t.date.year != _month!.year ||
                  t.date.month != _month!.month) {
                return false;
              }
            }
            if (_type != null && t.type != _type) return false;
            if (_accountId != null &&
                t.accountId != _accountId &&
                t.toAccountId != _accountId) {
              return false;
            }
            return true;
          }).toList();
          final code = data.currencyCode;
          final spent = filtered
              .where((t) => t.type == TxnType.expense)
              .fold(0, (a, t) => a + t.amountMinor - t.reimbursableMinor);
          final received = filtered
              .where((t) => t.type == TxnType.income)
              .fold(0, (a, t) => a + t.amountMinor);

          return Column(
            children: [
              // -- Month selector -------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _month == null ? null : () => _shiftMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous month',
                    ),
                    Expanded(
                      child: Center(
                        child: TextButton(
                          onPressed: () => setState(
                            () => _month = _month == null
                                ? DateTime(
                                    DateTime.now().year,
                                    DateTime.now().month,
                                  )
                                : null,
                          ),
                          child: Text(
                            _month == null
                                ? 'All time'
                                : DateFormat.yMMMM().format(_month!),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _month == null ? null : () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next month',
                    ),
                  ],
                ),
              ),
              // -- Filter chips ---------------------------------------------
              SingleChildScrollView(
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
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    const SizedBox(width: AppSpacing.sm),
                    // Account filter
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _accountId,
                        hint: const Text('All accounts'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All accounts'),
                          ),
                          for (final a in data.accounts)
                            DropdownMenuItem<String?>(
                              value: a.id,
                              child: Text(a.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _accountId = v),
                      ),
                    ),
                  ],
                ),
              ),
              // -- Filtered totals ------------------------------------------
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
                      'Out ${Money.format(spent, code: code)}'
                      ' · In ${Money.format(received, code: code)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // -- List ------------------------------------------------------
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('Nothing matches these filters.'),
                      )
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
        },
      ),
    );
  }
}
