import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// A person a detected transaction might square up with.
@immutable
final class SettleSuggestion {
  const SettleSuggestion({
    required this.position,
    required this.kind,
    required this.openMinor,
    required this.exactAmount,
    required this.namedInText,
  });

  final PersonPosition position;
  final DebtKind kind;

  /// The person's net balance in [kind]'s direction — what a settlement of
  /// that size would clear to zero. Always positive.
  final int openMinor;

  /// The detected amount is exactly [openMinor].
  final bool exactAmount;

  /// The person's name appears in the alert text.
  final bool namedInText;
}

/// Which open balances a detected transaction could settle, and what applying
/// it records.
///
/// Settling reuses the ledger's own settlement: the saved transaction becomes a
/// settlement with the person ([PeopleLedger.settlementTxn]), so the normal
/// oldest-first allocation clears their debts and a person brought to zero
/// drops out of [PeopleLedger.openPositions].
abstract final class SettleMatch {
  /// Money in can only clear "they owe you"; money out only "you owe them". A
  /// transfer between the owner's own accounts settles nothing.
  static DebtKind? kindFor(TxnType type) => switch (type) {
    TxnType.income => DebtKind.owedToYou,
    TxnType.expense => DebtKind.youOwe,
    TxnType.transfer => null,
  };

  /// Everyone with an open balance in the direction [type] can clear, most
  /// likely first: an exact amount match, then a name the alert mentions, then
  /// the largest balance.
  static List<SettleSuggestion> suggest({
    required List<PersonPosition> positions,
    required TxnType type,
    required int? amountMinor,
    required String text,
  }) {
    final kind = kindFor(type);
    if (kind == null) return const [];
    final out = <SettleSuggestion>[];
    for (final p in positions) {
      final open = kind == DebtKind.owedToYou ? p.netMinor : -p.netMinor;
      if (open <= 0) continue;
      out.add(
        SettleSuggestion(
          position: p,
          kind: kind,
          openMinor: open,
          exactAmount: amountMinor == open,
          namedInText: mentions(text, p),
        ),
      );
    }
    out.sort((a, b) {
      if (a.exactAmount != b.exactAmount) return a.exactAmount ? -1 : 1;
      if (a.namedInText != b.namedInText) return a.namedInText ? -1 : 1;
      final bySize = b.openMinor.compareTo(a.openMinor);
      if (bySize != 0) return bySize;
      return a.position.name.toLowerCase().compareTo(
        b.position.name.toLowerCase(),
      );
    });
    return out;
  }

  /// True when any word of the person's name (three letters or more, so an
  /// initial never matches) appears as a whole word in [text]. The unnamed
  /// bucket has no name to find.
  static bool mentions(String text, PersonPosition p) {
    if (p.key.isEmpty) return false;
    for (final word in p.name.trim().split(RegExp(r'\s+'))) {
      if (word.length < 3) continue;
      final pattern = RegExp(
        '(^|[^\\p{L}\\p{N}])${RegExp.escape(word)}(\$|[^\\p{L}\\p{N}])',
        caseSensitive: false,
        unicode: true,
      );
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  /// What saving [base] as a settlement with [s] records.
  ///
  /// Up to the open balance the money is a settlement — neither income nor
  /// spending. A partial amount leaves the rest still owed. Anything above the
  /// balance was never owed, so it stays an ordinary transaction of [base]'s
  /// type (keeping its category) instead of vanishing into an over-cleared
  /// settlement. The settlement comes first: it is the transaction the notice
  /// links to.
  static List<Txn> apply({
    required Txn base,
    required SettleSuggestion s,
    required String Function() newId,
  }) {
    assert(kindFor(base.type) == s.kind, 'direction must match the balance');
    final settled = base.amountMinor < s.openMinor
        ? base.amountMinor
        : s.openMinor;
    final settlement = PeopleLedger.settlementTxn(
      id: base.id,
      person: s.position.key.isEmpty ? '' : s.position.name,
      personId: s.position.personId,
      kind: s.kind,
      amountMinor: settled,
      accountId: base.accountId,
      date: base.date,
      note: base.note,
      createdAt: base.createdAt,
    );
    final excess = base.amountMinor - settled;
    if (excess == 0) return [settlement];
    return [
      settlement,
      Txn(
        id: newId(),
        type: base.type,
        amountMinor: excess,
        date: base.date,
        accountId: base.accountId,
        categoryId: base.categoryId,
        note: base.note,
        createdAt: base.createdAt,
      ),
    ];
  }

  /// Turns an already-saved income or expense into a settlement with [s],
  /// keeping its id so anything pointing at it — a captured notice — still
  /// does. Only offered when the amount fits inside the open balance, so the
  /// cash is never split after the fact.
  static Txn relink(Txn txn, SettleSuggestion s) {
    assert(txn.amountMinor <= s.openMinor, 'relink never over-clears');
    return PeopleLedger.settlementTxn(
      id: txn.id,
      person: s.position.key.isEmpty ? '' : s.position.name,
      personId: s.position.personId,
      kind: s.kind,
      amountMinor: txn.amountMinor,
      accountId: txn.accountId,
      date: txn.date,
      note: txn.note,
      createdAt: txn.createdAt,
    );
  }
}
