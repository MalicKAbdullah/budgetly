import 'package:flutter/foundation.dart' show immutable;

/// What a transaction does to the accounts.
/// - [expense]  money leaves [Txn.accountId], attributed to a category.
/// - [income]   money enters [Txn.accountId] (e.g. salary).
/// - [transfer] money moves [Txn.accountId] → [Txn.toAccountId] (e.g. ATM
///   withdrawal). Not spending — it never counts against budgets.
enum TxnType {
  expense('Expense'),
  income('Income'),
  transfer('Transfer');

  const TxnType(this.label);
  final String label;

  static TxnType parse(String? raw) => TxnType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => TxnType.expense,
  );
}

/// A single money movement.
///
/// Money invariants the whole app relies on:
/// - [amountMinor] is always the cash that really moved through the owner's
///   own account, so account balances are simply the sum of it.
/// - [ownShareMinor] is what the movement actually cost the owner: their cash
///   out, minus the part others owe them back, plus the part of their share
///   someone else fronted.
/// - A **settlement** ([isSettlement]) only passes money through the owner to
///   clear a debt. It moves cash but is never income and never spending.
@immutable
final class Txn {
  const Txn({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    this.reimbursableMinor = 0,
    this.payableMinor = 0,
    this.counterparty = '',
    this.settlement = false,
    this.reimbursesTxnId,
    required this.createdAt,
  });

  factory Txn.fromJson(Map<String, dynamic> json) => Txn(
    id: json['id'] as String,
    type: TxnType.parse(json['type'] as String?),
    amountMinor: (json['amountMinor'] as num).toInt(),
    date: DateTime.parse(json['date'] as String),
    accountId: json['accountId'] as String,
    toAccountId: json['toAccountId'] as String?,
    categoryId: json['categoryId'] as String?,
    note: json['note'] as String? ?? '',
    reimbursableMinor: (json['reimbursableMinor'] as num?)?.toInt() ?? 0,
    payableMinor: (json['payableMinor'] as num?)?.toInt() ?? 0,
    counterparty: json['counterparty'] as String? ?? '',
    settlement: json['settlement'] as bool? ?? false,
    reimbursesTxnId: json['reimbursesTxnId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final TxnType type;

  /// Cash that moved through [accountId]. For a bill someone else fronted in
  /// full this is 0 — no cash left the owner's account.
  final int amountMinor;
  final DateTime date;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String note;

  /// Part of an [TxnType.expense] the owner fronted for others and expects
  /// back — a receivable. Always ≤ [amountMinor].
  final int reimbursableMinor;

  /// Part of the owner's own share of an [TxnType.expense] that somebody else
  /// paid for them — a payable. It is the owner's cost even though no cash of
  /// theirs moved, and it is a debt until settled.
  final int payableMinor;

  /// Free-text name of the other person in a split or settlement. Empty when
  /// unnamed (older data), which the People view groups as "Unspecified".
  final String counterparty;

  /// True when this transaction only passes money through the owner to clear a
  /// debt: receiving a repayment (income) or paying someone back (expense).
  final bool settlement;

  /// Legacy per-transaction settlement link: when set, this transaction repays
  /// the expense with this id specifically.
  final String? reimbursesTxnId;

  final DateTime createdAt;

  /// A settlement is money in transit — never income, never spending.
  bool get isSettlement => settlement || reimbursesTxnId != null;

  /// Kept for older call sites; a repayment is just a settlement.
  bool get isReimbursement => isSettlement;

  bool get isSplit => reimbursableMinor > 0 || payableMinor > 0;

  /// What this movement actually cost (expense) or earned (income) the owner.
  /// Zero for settlements and transfers, which move money without changing it.
  int get ownShareMinor {
    if (isSettlement) return 0;
    return switch (type) {
      TxnType.expense => amountMinor - reimbursableMinor + payableMinor,
      TxnType.income => amountMinor,
      TxnType.transfer => 0,
    };
  }

  Txn copyWith({
    TxnType? type,
    int? amountMinor,
    DateTime? date,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
    int? reimbursableMinor,
    int? payableMinor,
    String? counterparty,
    bool? settlement,
    String? reimbursesTxnId,
  }) => Txn(
    id: id,
    type: type ?? this.type,
    amountMinor: amountMinor ?? this.amountMinor,
    date: date ?? this.date,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId ?? this.toAccountId,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    reimbursableMinor: reimbursableMinor ?? this.reimbursableMinor,
    payableMinor: payableMinor ?? this.payableMinor,
    counterparty: counterparty ?? this.counterparty,
    settlement: settlement ?? this.settlement,
    reimbursesTxnId: reimbursesTxnId ?? this.reimbursesTxnId,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amountMinor': amountMinor,
    'date': date.toIso8601String(),
    'accountId': accountId,
    if (toAccountId != null) 'toAccountId': toAccountId,
    if (categoryId != null) 'categoryId': categoryId,
    'note': note,
    'reimbursableMinor': reimbursableMinor,
    if (payableMinor != 0) 'payableMinor': payableMinor,
    if (counterparty.isNotEmpty) 'counterparty': counterparty,
    if (settlement) 'settlement': true,
    if (reimbursesTxnId != null) 'reimbursesTxnId': reimbursesTxnId,
    'createdAt': createdAt.toIso8601String(),
  };
}
