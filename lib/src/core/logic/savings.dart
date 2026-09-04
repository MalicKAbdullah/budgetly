import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// One transaction's savings movement, with where the amount came from.
@immutable
final class SavingsMovement {
  const SavingsMovement({
    required this.txn,
    required this.effectMinor,
    required this.fromCategoryRule,
  });

  final Txn txn;

  /// Signed and never zero: positive reserved, negative released.
  final int effectMinor;

  /// True when the amount comes from the category's rule rather than an
  /// earmark set on this one transaction.
  final bool fromCategoryRule;

  bool get isDeposit => effectMinor > 0;
}

/// What the bulk earmark action does to a selection of transactions.
enum SavingsBulkAction {
  moveToSavings('Move to savings'),
  takeFromSavings('Take from savings'),
  resetToCategory('Reset to category default');

  const SavingsBulkAction(this.label);
  final String label;
}

/// Savings as an **earmark**: a pot reserved across every account, never an
/// account of its own — the owner's money moves between cash, bank and wallet
/// constantly, and cash can be savings too.
///
/// **The invariant.** Earmarking is neither spending nor income and moves no
/// cash. So an earmark leaves account balances and net worth alone, and the
/// earmarked part of a transaction is taken out of Spent, Income, budgets, the
/// category breakdown, the spend chart and the statement — the same treatment
/// a settlement gets, for the same reason: the money did not change hands with
/// the outside world.
///
/// **One resolver.** [effectFor] is the only place a savings amount is decided,
/// and every derived number and screen goes through it. That is what makes a
/// category rule retroactive: the rule is read at the moment a number is
/// computed, so marking a category "adds to savings" counts every transaction
/// already in it without touching one record.
abstract final class Savings {
  /// The savings movement [txn] represents, in signed minor units.
  ///
  /// An earmark set on the transaction wins over its category's rule, and an
  /// explicit `0` deliberately opts one transaction out of that rule.
  static int effectFor(Txn txn, AppData data) {
    // A transfer shuffles money between the owner's own accounts. Nothing
    // about how much of the total is reserved changes, whatever its category
    // says — so a transfer can never carry an effect.
    if (txn.type == TxnType.transfer) return 0;
    final own = txn.savingsEffectMinor;
    if (own != null) return own;
    final category = data.categoryById(txn.categoryId);
    if (category == null) return 0;
    return switch (category.savingsEffect) {
      SavingsEffect.none => 0,
      SavingsEffect.addsToSavings => txn.ownShareMinor,
      SavingsEffect.takesFromSavings => -txn.ownShareMinor,
    };
  }

  /// True when [txn] carries its own earmark rather than inheriting one.
  static bool hasOwnEarmark(Txn txn) => txn.savingsEffectMinor != null;

  /// The part of [txn] that is only reserved or released, never earned or
  /// spent.
  static int earmarkedMinor(Txn txn, AppData data) =>
      effectFor(txn, data).abs();

  /// What [txn] contributes to Spent / Income: the owner's share of it minus
  /// the part that was only earmarked. **Every** flow roll-up uses this, so no
  /// screen can accidentally read an earmark as money earned or spent.
  static int spendableShareMinor(Txn txn, AppData data) =>
      txn.ownShareMinor - earmarkedMinor(txn, data);

  /// Everything reserved right now — a running balance over **all**
  /// transactions, never scoped to the selected window.
  static int reservedMinor(AppData data) =>
      data.txns.fold(0, (sum, t) => sum + effectFor(t, data));

  /// Every penny the owner has, across all active accounts.
  static int totalMinor(AppData data) => Balances.netWorthMinor(data);

  /// What is free to spend without eating into savings. Negative is real and
  /// meaningful: the reserved pot is no longer fully covered.
  static int safeToSpendMinor(AppData data) =>
      totalMinor(data) - reservedMinor(data);

  /// The owner's "+/-": how far the reserved pot is ahead of (positive) or
  /// short of (negative) the target.
  static int varianceMinor(AppData data) =>
      reservedMinor(data) - data.savingsTargetMinor;

  /// True when money that was earmarked has already been spent — the warning
  /// this whole feature exists to raise.
  static bool isDipping(AppData data) => totalMinor(data) < reservedMinor(data);

  /// Net reserved inside an inclusive day range — the shared period filter's
  /// window.
  static int savedInRangeMinor(AppData data, DateTime start, DateTime end) =>
      data.txns
          .where((t) => DashboardFlow.inRange(t.date, start, end))
          .fold(0, (sum, t) => sum + effectFor(t, data));

  /// Every transaction that moves savings, newest first. Pass a range to limit
  /// it to the selected window.
  static List<SavingsMovement> movements(
    AppData data, {
    DateTime? start,
    DateTime? end,
  }) {
    final rows = <SavingsMovement>[];
    for (final t in data.txns) {
      if (start != null &&
          end != null &&
          !DashboardFlow.inRange(t.date, start, end)) {
        continue;
      }
      final effect = effectFor(t, data);
      if (effect == 0) continue;
      rows.add(
        SavingsMovement(
          txn: t,
          effectMinor: effect,
          fromCategoryRule: !hasOwnEarmark(t),
        ),
      );
    }
    rows.sort((a, b) => b.txn.date.compareTo(a.txn.date));
    return rows;
  }

  /// The earmark [action] would write onto [txn]: the whole of what the
  /// transaction cost or earned, or `null` to hand it back to its category.
  static int? bulkEarmarkFor(Txn txn, SavingsBulkAction action) =>
      switch (action) {
        SavingsBulkAction.moveToSavings => txn.ownShareMinor,
        SavingsBulkAction.takeFromSavings => -txn.ownShareMinor,
        SavingsBulkAction.resetToCategory => null,
      };

  /// Applies [action] to every transaction in [txnIds] at once, returning the
  /// whole next snapshot so the caller persists it in a single commit.
  static AppData applied(
    AppData data,
    Set<String> txnIds,
    SavingsBulkAction action,
  ) => data.copyWith(
    txns: [
      for (final t in data.txns)
        if (txnIds.contains(t.id))
          t.copyWith(savingsEffectMinor: bulkEarmarkFor(t, action))
        else
          t,
    ],
  );
}
