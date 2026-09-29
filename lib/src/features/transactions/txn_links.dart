import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/settle_match.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/features/people/settle_suggestions.dart';

/// What this transaction means for the split ledger: for a settlement, who it
/// squares up with; for a split, how much of it is still open. Null when the
/// transaction is neither.
Widget? txnLinkCard(AppData data, Txn txn) {
  if (txn.isSettlement) return _SettlementCard(data: data, txn: txn);
  if (txn.type == TxnType.expense && txn.isSplit) {
    return _SplitCard(data: data, txn: txn);
  }
  return null;
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.data, required this.txn});
  final AppData data;
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final code = data.currencyCode;
    final original = txn.reimbursesTxnId == null
        ? null
        : data.txnById(txn.reimbursesTxnId!);
    final personKey =
        txn.personId ??
        PeopleLedger.keyForName(
          data,
          txn.counterparty.trim().isEmpty && original != null
              ? original.counterparty
              : txn.counterparty,
        );

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: Text(SplitText.settlementTitle(txn)),
            subtitle: const Text(
              'Money passing through — not counted as income or spending. '
              'It clears the oldest debt first.',
            ),
            trailing: MoneyTrailing(
              amount: Money.format(txn.amountMinor, code: code),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.people_outline, size: 20),
            title: const Text('Open the balance with this person'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.push('/people/${PeopleLedger.routeKeyFor(personKey)}'),
          ),
          if (original != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link, size: 20),
              title: const Text('Settles this expense'),
              subtitle: Text(
                '${original.note.isNotEmpty ? original.note : data.categoryById(original.categoryId)?.name ?? 'Expense'}'
                ' · ${DateFormat.yMMMd().format(original.date)}',
              ),
              onTap: () => context.push('/txn/${original.id}'),
            ),
        ],
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.data, required this.txn});
  final AppData data;
  final Txn txn;

  @override
  Widget build(BuildContext context) {
    final code = data.currencyCode;
    final person = SplitText.personLabel(txn.counterparty);
    final receivable = txn.reimbursableMinor > 0;
    final people = txn.splits;
    final kind = receivable ? DebtKind.owedToYou : DebtKind.youOwe;
    final original = receivable ? txn.reimbursableMinor : txn.payableMinor;
    final open = PeopleLedger.outstandingForMinor(data, txn, kind);

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.call_split),
            title: Text(receivable ? 'Owed back to you' : 'You owe $person'),
            subtitle: Text(
              '${SplitText.describe(txn, code)}\n'
              '${Money.format(original - open, code: code)} of '
              '${Money.format(original, code: code)} settled',
            ),
            isThreeLine: true,
            trailing: MoneyTrailing(
              amount: Money.format(open, code: code),
              secondary: 'left',
            ),
          ),
          if (people.isEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.people_outline, size: 20),
              title: Text('Settle up with $person'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/people/'
                '${PeopleLedger.routeKeyFor(PeopleLedger.keyForName(data, txn.counterparty))}',
              ),
            )
          else
            for (final s in people)
              ListTile(
                dense: true,
                leading: const Icon(Icons.people_outline, size: 20),
                title: Text(
                  '${data.personById(s.personId)?.name ?? PeopleLedger.unnamedLabel}'
                  ' · ${Money.format(s.amountMinor, code: code)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/people/${PeopleLedger.routeKeyFor(s.personId)}',
                ),
              ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

/// Links an already-saved income or expense to a person's balance, for money
/// that was recorded before anyone realised it was a repayment. Offered only
/// for balances the whole amount fits inside — [SettleMatch.relink] never
/// splits cash after the fact. Empty when nobody qualifies.
class TxnSettleLinkSection extends ConsumerWidget {
  const TxnSettleLinkSection({
    required this.data,
    required this.txn,
    super.key,
  });
  final AppData data;
  final Txn txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (txn.isSettlement || txn.isSplit) return const SizedBox.shrink();
    final suggestions = SettleMatch.suggest(
      positions: PeopleLedger.openPositions(data),
      type: txn.type,
      amountMinor: txn.amountMinor,
      text: txn.note,
    ).where((s) => s.openMinor >= txn.amountMinor).toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: SettleSuggestionPicker(
        suggestions: suggestions,
        selectedKey: null,
        amountMinor: txn.amountMinor,
        code: data.currencyCode,
        onChanged: (s) async {
          if (s == null) return;
          final router = GoRouter.of(context);
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Settle with ${s.position.name}?'),
              content: Text(
                '${SettleSuggestionPicker.outcomeText(s, txn.amountMinor, data.currencyCode)} '
                'This stops counting as '
                '${txn.type == TxnType.income ? 'income' : 'spending'}.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Settle'),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await ref.read(appDataProvider.notifier).linkTxnToBalance(txn, s);
          router.pop();
        },
      ),
    );
  }
}
