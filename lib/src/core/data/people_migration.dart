import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// Turns the free-text `counterparty` names that versions up to v0.11.0 wrote
/// into real [Person] records, and the scalar split amounts into [TxnSplit]
/// slices pointing at them.
///
/// Guarantees the live vault depends on:
/// - **Money is never touched.** `amountMinor`, `reimbursableMinor` and
///   `payableMinor` are copied as they are; only person references are added.
/// - **Idempotent.** A second run finds every name registered and every split
///   already sliced, so it returns the *same instance* — which is how the
///   caller knows not to rewrite the vault.
/// - **Nothing is invented.** A transaction with no name keeps none, so the
///   unnamed ("Unspecified") bucket survives exactly as it is.
abstract final class PeopleMigration {
  /// [newId] mints ids for the people that get created (uuid in the app, a
  /// counter in tests).
  static AppData run(AppData data, {required String Function() newId}) {
    final people = [...data.people];
    final byName = <String, Person>{for (final p in people) p.nameKey: p};

    Person register(String name) {
      final key = name.trim().toLowerCase();
      final known = byName[key];
      if (known != null) return known;
      final created = Person(id: newId(), name: name.trim());
      byName[key] = created;
      people.add(created);
      return created;
    }

    var txnsChanged = false;
    final txns = <Txn>[];
    for (final t in data.txns) {
      final name = t.counterparty.trim();
      if (name.isEmpty) {
        txns.add(t);
        continue;
      }
      // Every name the owner ever typed becomes a record, so it can be reused
      // and renamed — even on a transaction that carries no split.
      final person = register(name);

      if (t.isSettlement) {
        if (t.personId == null) {
          txns.add(t.copyWith(personId: person.id));
          txnsChanged = true;
        } else {
          txns.add(t);
        }
        continue;
      }

      // Both directions at once cannot be expressed as one-directional slices.
      // Such a record (only reachable from very old hand-edited data) keeps its
      // scalars and stays in the legacy read path.
      final oneDirection = t.reimbursableMinor == 0 || t.payableMinor == 0;
      if (t.type == TxnType.expense &&
          t.isSplit &&
          t.splits.isEmpty &&
          oneDirection) {
        txns.add(
          t.copyWith(
            splits: [
              TxnSplit(personId: person.id, amountMinor: t.splitTotalMinor),
            ],
          ),
        );
        txnsChanged = true;
        continue;
      }
      txns.add(t);
    }

    final peopleChanged = people.length != data.people.length;
    if (!txnsChanged && !peopleChanged) return data;
    return data.copyWith(
      people: peopleChanged ? people : data.people,
      txns: txnsChanged ? txns : data.txns,
    );
  }
}
