import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';

/// Plain-language wording for split expenses and settlements, so a full bill
/// the owner merely fronted can never be read as their own spending.
abstract final class SplitText {
  /// One line spelling out the split, or null when there is nothing to spell
  /// out. Always leads with the owner's share — the real expense.
  static String? describe(Txn t, String code) {
    if (t.isSettlement || !t.isSplit) return null;
    final who = t.counterparty.trim();
    final parts = <String>[
      'Your share ${Money.format(t.ownShareMinor, code: code)}',
    ];

    if (t.amountMinor > 0) {
      parts.add('you paid ${Money.format(t.amountMinor, code: code)}');
    }
    if (t.reimbursableMinor > 0) {
      final owed = Money.format(t.reimbursableMinor, code: code);
      parts.add(who.isEmpty ? '$owed owed to you' : '$owed owed by $who');
    }
    if (t.payableMinor > 0) {
      final owe = Money.format(t.payableMinor, code: code);
      if (t.amountMinor == 0) {
        parts.add(who.isEmpty ? '$owe paid for you' : '$who paid');
      }
      parts.add(who.isEmpty ? 'you owe $owe' : 'you owe $who $owe');
    }
    return parts.join(' · ');
  }

  /// Row title for a settlement: cash that only passes through the owner.
  static String settlementTitle(Txn t) {
    final who = t.counterparty.trim();
    if (t.type == TxnType.income) {
      return who.isEmpty ? 'Settlement received' : 'Paid back by $who';
    }
    return who.isEmpty ? 'Settlement paid' : 'Paid back $who';
  }

  /// The short badge shown instead of "Income"/"Expense" on a settlement.
  static const String settlementBadge = 'Settlement · not income or spending';

  static String personLabel(String counterparty) => counterparty.trim().isEmpty
      ? PeopleLedger.unnamedLabel
      : counterparty.trim();
}
