import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';

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
            trailing: Text(
              Money.format(txn.amountMinor, code: code),
              style: const TextStyle(fontWeight: FontWeight.bold),
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
            trailing: Text(
              '${Money.format(open, code: code)} left',
              style: const TextStyle(fontWeight: FontWeight.bold),
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
