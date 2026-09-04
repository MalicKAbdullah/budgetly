import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';
import 'package:budgetly/src/features/savings/widgets/savings_movement_tile.dart';

/// Earmark transactions that were recorded before there was a savings rule —
/// or that will never share a category. Pick as many as you like; the chosen
/// action is written to all of them in one commit.
class SavingsBulkScreen extends ConsumerStatefulWidget {
  const SavingsBulkScreen({super.key});

  @override
  ConsumerState<SavingsBulkScreen> createState() => _SavingsBulkScreenState();
}

class _SavingsBulkScreenState extends ConsumerState<SavingsBulkScreen> {
  final _selected = <String>{};

  /// Only movements that can carry an earmark are offered. A transfer never
  /// changes how much is reserved, and a settlement only passes money through,
  /// so neither has anything to earmark.
  List<Txn> _candidates(AppData data, DateTime start, DateTime end) =>
      data.txns
          .where(
            (t) =>
                t.type != TxnType.transfer &&
                !t.isSettlement &&
                DashboardFlow.inRange(t.date, start, end),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  Future<void> _apply(SavingsBulkAction action) async {
    final ids = {..._selected};
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(appDataProvider.notifier).applySavingsAction(ids, action);
    if (!mounted) return;
    setState(_selected.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${action.label} · ${ids.length} transactions updated'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = DateTime.now();
    final filter = ref.watch(periodFilterProvider);
    final (start, end) = filter.resolve(now);
    final rows = _candidates(data, start, end);
    final code = data.currencyCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? 'Earmark transactions'
              : '${_selected.length} selected',
        ),
        actions: [
          if (rows.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == rows.length) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(rows.map((t) => t.id));
                }
              }),
              child: Text(
                _selected.length == rows.length ? 'Clear' : 'Select all',
              ),
            ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                _apply(SavingsBulkAction.moveToSavings),
                            icon: const Icon(Icons.savings_outlined, size: 18),
                            label: const Text('Move to savings'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () =>
                                _apply(SavingsBulkAction.takeFromSavings),
                            icon: const Icon(Icons.output_outlined, size: 18),
                            label: const Text('Take from savings'),
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () =>
                          _apply(SavingsBulkAction.resetToCategory),
                      child: const Text('Reset to category default'),
                    ),
                  ],
                ),
              ),
            ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: PeriodFilterBar(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'No expenses or income in the selected window. Widen '
                        'the date range above.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final t = rows[i];
                      final effect = Savings.effectFor(t, data);
                      final own = Savings.hasOwnEarmark(t);
                      return CheckboxListTile(
                        value: _selected.contains(t.id),
                        onChanged: (on) => setState(() {
                          if (on ?? false) {
                            _selected.add(t.id);
                          } else {
                            _selected.remove(t.id);
                          }
                        }),
                        title: Text(
                          savingsTxnLabel(t, data),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${DateFormat.yMMMd().format(t.date)} · '
                          '${Money.format(t.ownShareMinor, code: code)}'
                          '${_effectSuffix(effect, own, code)}',
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _effectSuffix(int effect, bool ownEarmark, String code) {
    if (effect == 0) return ownEarmark ? ' · not savings' : '';
    final amount = Money.format(effect.abs(), code: code);
    final source = ownEarmark ? 'earmarked' : 'by category';
    return effect > 0
        ? ' · +$amount savings ($source)'
        : ' · -$amount savings ($source)';
  }
}
