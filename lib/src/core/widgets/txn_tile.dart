import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';

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
    final c = SuiteColors.of(context);

    final headline = txn.isSettlement || txn.type != TxnType.expense
        ? txn.amountMinor
        : txn.ownShareMinor;
    final splitLine = SplitText.describe(txn, code);
    // Who is on it, when it is shared with more than one person — the
    // per-person amounts live on the transaction screen.
    final peopleLine = txn.splits.length > 1
        ? 'Split ${txn.splits.length} ways'
        : null;

    final meta = [
      data.accountById(txn.accountId)?.name ?? '',
      DateFormat.MMMd().format(txn.date),
      if (txn.note.isNotEmpty && txn.type != TxnType.income) txn.note,
    ].where((s) => s.isNotEmpty).join(' · ');

    final secondary = AppTextStyles.bodySmall.copyWith(color: c.textSecondary);
    final title = _title();

    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 66),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.smd,
            ),
            child: Row(
              children: [
                _leading(context, c, title),
                const SizedBox(width: AppSpacing.smd + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (splitLine != null)
                        Text(
                          splitLine,
                          maxLines: 2,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      if (peopleLine != null)
                        Text(
                          peopleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      if (txn.isSettlement)
                        Text(
                          SplitText.settlementBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary,
                        ),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.smd),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _amount(c, headline, code),
                      if (splitLine != null && txn.amountMinor != headline) ...[
                        const SizedBox(height: 2),
                        ValueText(
                          'of ${Money.format(txn.amountMinor, code: code)}',
                          style: AppTextStyles.caption,
                          color: c.textTertiary,
                          alignment: AlignmentDirectional.centerEnd,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading(BuildContext context, SuiteColors c, String title) {
    if (txn.isSettlement) {
      return const IconBadge(icon: Icons.handshake_outlined);
    }
    return switch (txn.type) {
      TxnType.expense => IconBadge(
        icon: CategoryVisual.icon(title),
        color: CategoryVisual.color(context, title),
      ),
      TxnType.income => IconBadge(
        icon: Icons.south_west_rounded,
        color: c.positive,
      ),
      TxnType.transfer => const IconBadge(icon: Icons.swap_horiz_rounded),
    };
  }

  Widget _amount(SuiteColors c, int headline, String code) {
    const style = AppTextStyles.number;
    const end = AlignmentDirectional.centerEnd;
    if (txn.isSettlement) {
      return AmountText(
        txn.type == TxnType.income ? headline : -headline,
        code: code,
        style: style,
        showPlus: true,
        color: c.textSecondary,
        alignment: end,
      );
    }
    return switch (txn.type) {
      TxnType.expense => AmountText(
        -headline,
        code: code,
        style: style,
        alignment: end,
      ),
      TxnType.income => AmountText(
        headline,
        code: code,
        style: style,
        tone: MoneyTone.signed,
        showPlus: true,
        alignment: end,
      ),
      TxnType.transfer => AmountText(
        headline,
        code: code,
        style: style,
        color: c.textSecondary,
        alignment: end,
      ),
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
