import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/models/person.dart';

/// One person's slice of a split transaction.
///
/// The slices only say *who* owes *how much* of the transaction's split total
/// ([Txn.reimbursableMinor] or [Txn.payableMinor], whichever direction the
/// transaction carries). Those two scalars stay the authoritative totals for
/// every money calculation, so a slice can never change what a transaction
/// cost the owner.
@immutable
final class TxnSplit {
  const TxnSplit({required this.personId, required this.amountMinor});

  factory TxnSplit.fromJson(Map<String, dynamic> json) => TxnSplit(
    personId: json['personId'] as String,
    amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
  );

  /// The [Person.id] this slice belongs to.
  final String personId;
  final int amountMinor;

  TxnSplit copyWith({int? amountMinor}) => TxnSplit(
    personId: personId,
    amountMinor: amountMinor ?? this.amountMinor,
  );

  Map<String, dynamic> toJson() => {
    'personId': personId,
    'amountMinor': amountMinor,
  };

  static int sumOf(Iterable<TxnSplit> splits) =>
      splits.fold(0, (s, e) => s + e.amountMinor);
}
