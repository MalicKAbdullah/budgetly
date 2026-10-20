import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// One slice of the owner's own share, filed under a category.
@immutable
final class CategoryPart {
  const CategoryPart({required this.categoryId, required this.amountMinor});

  /// Null files the part as Uncategorized.
  final String? categoryId;
  final int amountMinor;
}

/// How one detected expense is divided: what others owe back ([people]) and
/// how the owner's own share is filed ([parts]).
///
/// The cash the alert reported is [totalMinor]; the people slices and the
/// category parts have to add up to it exactly. Saving produces ordinary
/// transactions, so activity, budgets and the people ledger read them with no
/// special case:
/// - the first transaction carries the first category part plus the whole
///   people total as its [Txn.reimbursableMinor], named by [Txn.splits] — the
///   same shape the transaction editor writes for "They owe me";
/// - every further category part is a plain expense of its own.
/// The cash of all of them adds up to [totalMinor], and each one's
/// [Txn.ownShareMinor] is exactly its category part.
@immutable
final class CaptureSplit {
  const CaptureSplit({
    required this.totalMinor,
    required this.people,
    required this.parts,
  });

  final int totalMinor;
  final List<TxnSplit> people;
  final List<CategoryPart> parts;

  int get owedBackMinor => TxnSplit.sumOf(people);
  int get filedMinor => parts.fold(0, (s, p) => s + p.amountMinor);

  /// Still to place: positive when the parts fall short of the total, negative
  /// when they overshoot it.
  int get remainingMinor => totalMinor - owedBackMinor - filedMinor;

  /// The reason this division cannot be saved, or null when it can.
  String? validate() {
    if (totalMinor <= 0) return 'Enter the amount first.';
    if (people.any((p) => p.amountMinor <= 0)) {
      return 'Give everyone on the split an amount, or remove them.';
    }
    if (parts.any((p) => p.amountMinor <= 0)) {
      return 'Give every category an amount, or remove it.';
    }
    final ids = parts.map((p) => p.categoryId).toSet();
    if (ids.length != parts.length) return 'Use each category only once.';
    if (people.isEmpty && parts.length < 2) {
      return 'Add a person or a second category to split this.';
    }
    if (owedBackMinor > totalMinor) {
      return 'The people owe more than the payment.';
    }
    if (parts.isEmpty && owedBackMinor < totalMinor) {
      return 'File your share under a category.';
    }
    final rest = remainingMinor;
    if (rest != 0) return rest > 0 ? 'Place the rest.' : 'Over the total.';
    return null;
  }

  /// The transactions this division records, the first being the one the
  /// notice links to. [counterparty] is the denormalized names of [people].
  List<Txn> toTxns({
    required Txn base,
    required String counterparty,
    required String Function() newId,
  }) {
    assert(validate() == null, 'only a valid split is saved');
    assert(base.type == TxnType.expense, 'only spending is split');
    assert(base.amountMinor == totalMinor, 'the split covers the alert');
    final first = parts.isEmpty ? null : parts.first;
    return [
      Txn(
        id: base.id,
        type: TxnType.expense,
        amountMinor: owedBackMinor + (first == null ? 0 : first.amountMinor),
        date: base.date,
        accountId: base.accountId,
        categoryId: first?.categoryId,
        note: base.note,
        reimbursableMinor: owedBackMinor,
        splits: people,
        counterparty: counterparty,
        createdAt: base.createdAt,
      ),
      for (final p in parts.skip(1))
        Txn(
          id: newId(),
          type: TxnType.expense,
          amountMinor: p.amountMinor,
          date: base.date,
          accountId: base.accountId,
          categoryId: p.categoryId,
          note: base.note,
          createdAt: base.createdAt,
        ),
    ];
  }
}
