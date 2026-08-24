import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people_allocation.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// Which way a split debt points.
enum DebtKind {
  /// The owner fronted money — the other person owes it back.
  owedToYou,

  /// The other person fronted the owner's share — the owner owes it.
  youOwe,
}

/// One person's slice of one split, with how much of it is still open after
/// settlements.
@immutable
final class DebtEntry {
  const DebtEntry({
    required this.txn,
    required this.kind,
    required this.originalMinor,
    required this.outstandingMinor,
  });

  final Txn txn;
  final DebtKind kind;
  final int originalMinor;
  final int outstandingMinor;

  int get settledMinor => originalMinor - outstandingMinor;
  bool get isOpen => outstandingMinor > 0;
}

/// Everything the owner and one person owe each other.
@immutable
final class PersonPosition {
  const PersonPosition({
    required this.key,
    required this.name,
    required this.entries,
    required this.settlements,
    this.personId,
  });

  /// Ledger identity: the [Person.id] once the person is a registry record,
  /// the lowercased name for a split that still only carries a typed name, and
  /// `''` for the unnamed bucket.
  final String key;

  /// The registry id, or null for the unnamed bucket and for names that are not
  /// registered records (only reachable from data the migration left alone).
  final String? personId;

  /// The person's name as it is displayed.
  final String name;

  /// Every split slice with this person, newest first.
  final List<DebtEntry> entries;

  /// Every settlement recorded with this person, newest first.
  final List<Txn> settlements;

  int get owedToYouMinor => _sum(DebtKind.owedToYou);
  int get youOweMinor => _sum(DebtKind.youOwe);

  /// Positive when they owe the owner, negative when the owner owes them.
  int get netMinor => owedToYouMinor - youOweMinor;

  bool get isClear => owedToYouMinor == 0 && youOweMinor == 0;

  List<DebtEntry> openEntries(DebtKind kind) =>
      entries.where((e) => e.kind == kind && e.isOpen).toList();

  int _sum(DebtKind kind) => entries
      .where((e) => e.kind == kind)
      .fold(0, (s, e) => s + e.outstandingMinor);
}

/// The per-person split ledger.
///
/// **Settle allocation rule.** A settlement clears that person's debts
/// **oldest first** (by transaction date, then by the order they were
/// entered). A settlement carrying a `reimbursesTxnId` — how older versions
/// recorded repayments — is applied to that one transaction first, and only
/// its excess joins the oldest-first pool. Money never over-clears a debt:
/// anything left over after every debt is cleared is simply unallocated (the
/// person's position reads as square).
///
/// **Identity.** A split names its people through [Txn.splits]; a settlement
/// through [Txn.personId]. Records the people migration did not rewrite are
/// still read through their typed `counterparty`, keyed by lowercased name
/// exactly as before — which is why a vault from any earlier version reads back
/// to the same numbers.
abstract final class PeopleLedger {
  /// The display name used for splits recorded before names existed.
  static const String unnamedLabel = 'Unspecified';

  static String keyOf(String name) => name.trim().toLowerCase();

  /// The ledger key for a typed name: the registry id when that name is a
  /// record, otherwise the lowercased name.
  static String keyForName(AppData data, String name) =>
      data.personByName(name)?.id ?? keyOf(name);

  /// A person key round-tripped through a route path segment. The unnamed
  /// bucket has an empty key, which a path segment cannot carry.
  static String routeKeyFor(String key) =>
      key.isEmpty ? '-' : Uri.encodeComponent(key);

  static String keyFromRoute(String segment) =>
      segment == '-' ? '' : Uri.decodeComponent(segment);

  static String displayNameFor(String key, String raw) =>
      raw.trim().isEmpty ? unnamedLabel : raw.trim();

  /// Distinct names available for reuse: every registered person, plus any name
  /// still living only on a transaction.
  static List<String> knownNames(AppData data) {
    final seen = <String, String>{};
    for (final p in data.people) {
      if (p.name.trim().isEmpty) continue;
      seen.putIfAbsent(p.nameKey, () => p.name.trim());
    }
    for (final t in data.txns) {
      final name = t.counterparty.trim();
      if (name.isEmpty) continue;
      seen.putIfAbsent(keyOf(name), () => name);
    }
    final names = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// The `counterparty` text that describes a set of slices. Kept in sync with
  /// [Txn.splits] so every screen that reads the denormalized name — the row
  /// subtitle, search — shows current names without knowing about the registry.
  static String counterpartyLabel(AppData data, List<TxnSplit> splits) => splits
      .map((s) => data.personById(s.personId)?.name.trim() ?? '')
      .where((n) => n.isNotEmpty)
      .join(', ');

  /// How many transactions still reference this person — by slice, by
  /// settlement, or by a name that has not been re-pointed. Deleting a person
  /// is only offered when this is zero.
  static int txnCountFor(AppData data, String personId) {
    final person = data.personById(personId);
    final nameKey = person?.nameKey ?? '';
    var count = 0;
    for (final t in data.txns) {
      final referenced =
          t.personId == personId ||
          t.splits.any((s) => s.personId == personId) ||
          (nameKey.isNotEmpty && keyOf(t.counterparty) == nameKey);
      if (referenced) count++;
    }
    return count;
  }

  /// Every person with at least one split plus every registered person,
  /// biggest absolute balance first, square people last.
  static List<PersonPosition> positions(AppData data) {
    final byKey = <String, PersonBucket>{};
    PersonBucket bucket(String key, String raw, {String? personId}) =>
        byKey.putIfAbsent(
          key,
          () => PersonBucket(key, displayNameFor(key, raw), personId),
        );

    // 0. Registered people always have a row, so a brand-new person can be
    //    opened, renamed and deleted before anything is split with them.
    for (final p in data.people) {
      bucket(p.id, p.name, personId: p.id);
    }

    // 1. Collect the split slices.
    for (final t in data.txns) {
      if (t.type != TxnType.expense || t.isSettlement || !t.isSplit) continue;
      if (t.splits.isEmpty) {
        // No named slices: the whole total is one debt, keyed by the typed
        // name (empty name → the unnamed bucket), exactly as before.
        final b = bucket(
          keyForName(data, t.counterparty),
          t.counterparty,
          personId: data.personByName(t.counterparty)?.id,
        );
        if (t.reimbursableMinor > 0) {
          b.debts.add(DebtSlice(t, DebtKind.owedToYou, t.reimbursableMinor));
        }
        if (t.payableMinor > 0) {
          b.debts.add(DebtSlice(t, DebtKind.youOwe, t.payableMinor));
        }
        continue;
      }
      final kind = t.splitsAreReceivable ? DebtKind.owedToYou : DebtKind.youOwe;
      for (final s in t.splits) {
        if (s.amountMinor <= 0) continue;
        final person = data.personById(s.personId);
        final b = bucket(
          person?.id ?? s.personId,
          person?.name ?? '',
          personId: person?.id,
        );
        b.debts.add(DebtSlice(t, kind, s.amountMinor));
      }
      // The invariant keeps this at zero; a vault edited by hand could still
      // leave part of the total unassigned, and it belongs in the unnamed
      // bucket rather than silently vanishing from the ledger.
      final unassigned = t.splitTotalMinor - TxnSplit.sumOf(t.splits);
      if (unassigned > 0) {
        bucket('', '').debts.add(DebtSlice(t, kind, unassigned));
      }
    }

    // 2. Collect the settlements.
    for (final t in data.txns) {
      if (!t.isSettlement) continue;
      final target = t.reimbursesTxnId == null
          ? null
          : data.txnById(t.reimbursesTxnId!);
      final key = _settlementKey(data, t, target);
      final person = data.personById(key);
      final b = bucket(
        key,
        person?.name ?? _settlementName(t, target),
        personId: person?.id,
      );
      b.settlements.add(t);
      if (target != null) {
        b.targeted.add(TargetedSettlement(t, target.id));
      } else {
        b.pool[kindOfSettlement(t)] =
            (b.pool[kindOfSettlement(t)] ?? 0) + t.amountMinor;
      }
    }

    final rows = byKey.values.map((b) => b.resolve()).toList()
      ..sort((a, b) {
        final byOpen = b.netMinor.abs().compareTo(a.netMinor.abs());
        if (byOpen != 0) return byOpen;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return rows;
  }

  /// Which bucket a settlement belongs to: its own person reference, then its
  /// typed name, then — for a legacy repayment that carries neither — the
  /// person of the expense it repays.
  static String _settlementKey(AppData data, Txn t, Txn? target) {
    if (t.personId != null) return t.personId!;
    if (t.counterparty.trim().isNotEmpty) {
      return keyForName(data, t.counterparty);
    }
    if (target == null) return '';
    if (target.splits.length == 1) return target.splits.single.personId;
    return keyForName(data, target.counterparty);
  }

  static String _settlementName(Txn t, Txn? target) =>
      t.counterparty.trim().isEmpty && target != null
      ? target.counterparty
      : t.counterparty;

  static PersonPosition? forKey(AppData data, String key) {
    final rows = positions(data);
    for (final p in rows) {
      if (p.key == key) return p;
    }
    // A key captured before the migration (the lowercased name) still opens the
    // person it named.
    final person = data.people.where((p) => p.nameKey == key).firstOrNull;
    if (person == null) return null;
    for (final p in rows) {
      if (p.key == person.id) return p;
    }
    return null;
  }

  /// People who still owe or are owed something.
  static List<PersonPosition> openPositions(AppData data) =>
      positions(data).where((p) => !p.isClear).toList();

  static int totalOwedToYouMinor(AppData data) =>
      positions(data).fold(0, (s, p) => s + p.owedToYouMinor);

  static int totalYouOweMinor(AppData data) =>
      positions(data).fold(0, (s, p) => s + p.youOweMinor);

  /// How much of one split is still open across everyone on it — used by the
  /// transaction detail.
  static int outstandingForMinor(AppData data, Txn txn, DebtKind kind) {
    var total = 0;
    for (final p in positions(data)) {
      for (final e in p.entries) {
        if (e.txn.id == txn.id && e.kind == kind) total += e.outstandingMinor;
      }
    }
    return total;
  }
}
