import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// Money received back clears "they owe you"; money paid out clears
/// "you owe them".
DebtKind kindOfSettlement(Txn settlement) =>
    settlement.type == TxnType.income ? DebtKind.owedToYou : DebtKind.youOwe;

/// One debt inside the allocation, tracking what is left of it.
final class DebtSlice {
  DebtSlice(this.txn, this.kind, this.originalMinor)
    : remaining = originalMinor;
  final Txn txn;
  final DebtKind kind;
  final int originalMinor;
  int remaining;
}

/// A legacy repayment that names the one expense it repays.
final class TargetedSettlement {
  TargetedSettlement(this.settlement, this.targetTxnId);
  final Txn settlement;
  final String targetTxnId;
}

/// Everything recorded with one person, before the settlements are
/// allocated across the debts.
final class PersonBucket {
  PersonBucket(this.key, this.name, this.personId);
  final String key;
  final String name;
  final String? personId;
  final List<DebtSlice> debts = [];
  final List<Txn> settlements = [];
  final List<TargetedSettlement> targeted = [];
  final Map<DebtKind, int> pool = {};

  PersonPosition resolve() {
    // Oldest first, ties broken by entry order then id so the allocation is
    // deterministic for identical dates.
    debts.sort((a, b) {
      final byDate = a.txn.date.compareTo(b.txn.date);
      if (byDate != 0) return byDate;
      final byCreated = a.txn.createdAt.compareTo(b.txn.createdAt);
      if (byCreated != 0) return byCreated;
      return a.txn.id.compareTo(b.txn.id);
    });

    // Targeted (legacy) settlements hit their own transaction first.
    final extra = Map<DebtKind, int>.from(pool);
    for (final t in targeted) {
      final kind = kindOfSettlement(t.settlement);
      var left = t.settlement.amountMinor;
      for (final d in debts) {
        if (d.txn.id != t.targetTxnId || d.kind != kind) continue;
        final take = left < d.remaining ? left : d.remaining;
        d.remaining -= take;
        left -= take;
        if (left == 0) break;
      }
      if (left > 0) extra[kind] = (extra[kind] ?? 0) + left;
    }

    // Everything else clears the oldest open debt first.
    for (final kind in DebtKind.values) {
      var left = extra[kind] ?? 0;
      if (left <= 0) continue;
      for (final d in debts) {
        if (d.kind != kind || d.remaining == 0) continue;
        final take = left < d.remaining ? left : d.remaining;
        d.remaining -= take;
        left -= take;
        if (left == 0) break;
      }
    }

    final entries =
        debts
            .map(
              (d) => DebtEntry(
                txn: d.txn,
                kind: d.kind,
                originalMinor: d.originalMinor,
                outstandingMinor: d.remaining,
              ),
            )
            .toList()
          ..sort((a, b) => b.txn.date.compareTo(a.txn.date));
    final sortedSettlements = [...settlements]
      ..sort((a, b) => b.date.compareTo(a.date));

    return PersonPosition(
      key: key,
      personId: personId,
      name: name,
      entries: entries,
      settlements: sortedSettlements,
    );
  }
}
