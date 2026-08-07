import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';

/// The transaction row used everywhere a transaction is listed.
///
/// The headline figure is always what the movement cost or earned the owner:
/// on a split that is their share, with the full bill spelled out underneath.
/// Settlements are labelled as such and shown in a neutral colour so they are
/// never read as income or spending.
class TxnTile extends StatelessWidget {
  const TxnTile({required this.txn, required this.data, this.onTap, super.key});

  final Txn txn;
  final AppData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final code = data.currencyCode;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (icon, color, sign) = _leadStyle(scheme);
    final headline = txn.isSettlement || txn.type != TxnType.expense
        ? txn.amountMinor
        : txn.ownShareMinor;
    final splitLine = SplitText.describe(txn, code);

    final meta = [
      data.accountById(txn.accountId)?.name ?? '',
      DateFormat.MMMd().format(txn.date),
      if (txn.note.isNotEmpty && txn.type != TxnType.income) txn.note,
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListTile(
      onTap: onTap,
      isThreeLine: splitLine != null || txn.isSettlement,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(_title(), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (splitLine != null)
            Text(
              splitLine,
              maxLines: 2,
              style: text.bodySmall?.copyWith(color: scheme.onSurface),
            ),
          if (txn.isSettlement)
            Text(
              SplitText.settlementBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign${Money.format(headline, code: code)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (splitLine != null && txn.amountMinor != headline)
            Text(
              'of ${Money.format(txn.amountMinor, code: code)}',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  (IconData, Color, String) _leadStyle(ColorScheme scheme) {
    if (txn.isSettlement) {
      return (
        Icons.handshake_outlined,
        scheme.onSurfaceVariant,
        txn.type == TxnType.income ? '+' : '-',
      );
    }
    return switch (txn.type) {
      TxnType.expense => (Icons.arrow_upward, scheme.error, '-'),
      TxnType.income => (Icons.arrow_downward, scheme.primary, '+'),
      TxnType.transfer => (Icons.swap_horiz, scheme.onSurfaceVariant, ''),
    };
  }

  String _title() {
    if (txn.isSettlement) return SplitText.settlementTitle(txn);
    return switch (txn.type) {
      TxnType.expense =>
        data.categoryById(txn.categoryId)?.name ?? 'Uncategorized',
      TxnType.income => txn.note.isEmpty ? 'Income' : txn.note,
      TxnType.transfer =>
        '${data.accountById(txn.accountId)?.name ?? '?'} → '
            '${data.accountById(txn.toAccountId)?.name ?? '?'}',
    };
  }
}
