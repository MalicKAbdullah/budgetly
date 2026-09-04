import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';

/// What a transaction is called on a savings list — the category for an
/// expense, the note for income, the two accounts for a transfer.
String savingsTxnLabel(Txn txn, AppData data) => switch (txn.type) {
  TxnType.expense => data.categoryById(txn.categoryId)?.name ?? 'Uncategorized',
  TxnType.income => txn.note.isEmpty ? 'Income' : txn.note,
  TxnType.transfer =>
    '${data.accountById(txn.accountId)?.name ?? '?'} → '
        '${data.accountById(txn.toAccountId)?.name ?? '?'}',
};

/// One savings movement: which transaction caused it, when, and whether the
/// amount came from the category's rule or from that transaction's own
/// earmark.
class SavingsMovementTile extends StatelessWidget {
  const SavingsMovementTile({
    required this.movement,
    required this.data,
    this.onTap,
    super.key,
  });

  final SavingsMovement movement;
  final AppData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final code = data.currencyCode;
    final deposit = movement.isDeposit;
    final color = deposit
        ? AppColors.success(brightness)
        : AppColors.warning(brightness);

    final meta = [
      DateFormat.yMMMd().format(movement.txn.date),
      data.accountById(movement.txn.accountId)?.name ?? '',
      movement.fromCategoryRule
          ? 'from this category\'s rule'
          : 'earmarked on this transaction',
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          deposit ? Icons.savings_outlined : Icons.output_outlined,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        savingsTxnLabel(movement.txn, data),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        meta,
        maxLines: 2,
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        '${deposit ? '+' : '-'}'
        '${Money.format(movement.effectMinor.abs(), code: code)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
