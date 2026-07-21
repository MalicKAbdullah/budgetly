import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// An expense the owner fronted for others, with money still owed back.
@immutable
final class Receivable {
  const Receivable({required this.expense, required this.owedMinor});

  final Txn expense;
  final int owedMinor;
}

/// "Who owes me" math: an expense's [Txn.reimbursableMinor] is a receivable;
/// income transactions tagged with `reimbursesTxnId` pay it down.
abstract final class Reimbursements {
  static int repaidForMinor(AppData data, String expenseId) => data.txns
      .where((t) => t.isReimbursement && t.reimbursesTxnId == expenseId)
      .fold(0, (sum, t) => sum + t.amountMinor);

  static int outstandingForMinor(AppData data, Txn expense) {
    if (expense.reimbursableMinor <= 0) return 0;
    final remaining =
        expense.reimbursableMinor - repaidForMinor(data, expense.id);
    return remaining.clamp(0, expense.reimbursableMinor);
  }

  /// Expenses with money still owed, most recent first.
  static List<Receivable> outstanding(AppData data) {
    final rows = <Receivable>[];
    for (final t in data.txns) {
      if (t.type != TxnType.expense || t.reimbursableMinor <= 0) continue;
      final owed = outstandingForMinor(data, t);
      if (owed > 0) rows.add(Receivable(expense: t, owedMinor: owed));
    }
    rows.sort((a, b) => b.expense.date.compareTo(a.expense.date));
    return rows;
  }

  static int totalOwedMinor(AppData data) =>
      outstanding(data).fold(0, (sum, r) => sum + r.owedMinor);
}
