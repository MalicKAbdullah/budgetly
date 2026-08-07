import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// Which way a split debt points.
enum DebtKind {
  /// The owner fronted money — the other person owes it back.
  owedToYou,

  /// The other person fronted the owner's share — the owner owes it.
  youOwe,
}

/// One split, with how much of it is still open after settlements.
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
  });

  /// Case-insensitive identity of the person; `''` for unnamed older splits.
  final String key;

  /// The name as the owner typed it (first spelling seen).
  final String name;

  /// Every split with this person, newest first.
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
abstract final class PeopleLedger {
  /// The display name used for splits recorded before names existed.
  static const String unnamedLabel = 'Unspecified';

  static String keyOf(String name) => name.trim().toLowerCase();

  /// A person key round-tripped through a route path segment. The unnamed
  /// bucket has an empty key, which a path segment cannot carry.
  static String routeKeyFor(String key) =>
      key.isEmpty ? '-' : Uri.encodeComponent(key);

  static String keyFromRoute(String segment) =>
      segment == '-' ? '' : Uri.decodeComponent(segment);

  static String displayNameFor(String key, String raw) =>
      raw.trim().isEmpty ? unnamedLabel : raw.trim();

  /// Distinct names already used, for the editor's autocomplete.
  static List<String> knownNames(AppData data) {
    final seen = <String, String>{};
    for (final t in data.txns) {
      final name = t.counterparty.trim();
      if (name.isEmpty) continue;
      seen.putIfAbsent(keyOf(name), () => name);
    }
    final names = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  /// Every person with at least one split, biggest absolute balance first,
  /// square people last.
  static List<PersonPosition> positions(AppData data) {
    final byKey = <String, _Bucket>{};
    _Bucket bucket(String key, String raw) =>
        byKey.putIfAbsent(key, () => _Bucket(key, displayNameFor(key, raw)));

    // 1. Collect the splits.
    for (final t in data.txns) {
      if (t.type != TxnType.expense || t.isSettlement || !t.isSplit) continue;
      final b = bucket(keyOf(t.counterparty), t.counterparty);
      if (t.reimbursableMinor > 0) {
        b.debts.add(_Debt(t, DebtKind.owedToYou, t.reimbursableMinor));
      }
      if (t.payableMinor > 0) {
        b.debts.add(_Debt(t, DebtKind.youOwe, t.payableMinor));
      }
    }

    // 2. Collect the settlements. A legacy one inherits the person of the
    //    expense it points at, so old data lands in the right bucket.
    for (final t in data.txns) {
      if (!t.isSettlement) continue;
      final target = t.reimbursesTxnId == null
          ? null
          : data.txnById(t.reimbursesTxnId!);
      final raw = target != null && t.counterparty.trim().isEmpty
          ? target.counterparty
          : t.counterparty;
      final b = bucket(keyOf(raw), raw);
      b.settlements.add(t);
      if (target != null) {
        b.targeted.add(_Targeted(t, target.id));
      } else {
        b.pool[_kindOf(t)] = (b.pool[_kindOf(t)] ?? 0) + t.amountMinor;
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

  static PersonPosition? forKey(AppData data, String key) {
    for (final p in positions(data)) {
      if (p.key == key) return p;
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

  /// How much of one split is still open — used by the transaction detail.
  static int outstandingForMinor(AppData data, Txn txn, DebtKind kind) {
    final p = forKey(data, keyOf(txn.counterparty));
    if (p == null) return 0;
    for (final e in p.entries) {
      if (e.txn.id == txn.id && e.kind == kind) return e.outstandingMinor;
    }
    return 0;
  }

  /// Money received back clears "they owe you"; money paid out clears
  /// "you owe them".
  static DebtKind _kindOf(Txn settlement) =>
      settlement.type == TxnType.income ? DebtKind.owedToYou : DebtKind.youOwe;
}

class _Debt {
  _Debt(this.txn, this.kind, this.originalMinor) : remaining = originalMinor;
  final Txn txn;
  final DebtKind kind;
  final int originalMinor;
  int remaining;
}

class _Targeted {
  _Targeted(this.settlement, this.targetTxnId);
  final Txn settlement;
  final String targetTxnId;
}

class _Bucket {
  _Bucket(this.key, this.name);
  final String key;
  final String name;
  final List<_Debt> debts = [];
  final List<Txn> settlements = [];
  final List<_Targeted> targeted = [];
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
      final kind = PeopleLedger._kindOf(t.settlement);
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
      name: name,
      entries: entries,
      settlements: sortedSettlements,
    );
  }
}
