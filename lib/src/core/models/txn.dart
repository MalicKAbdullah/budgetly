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

/// A single money movement. [reimbursableMinor] (Phase 2) is reserved for the
/// split/"owed back" feature; it defaults to 0 and is ignored for now.
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
    reimbursesTxnId: json['reimbursesTxnId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final TxnType type;
  final int amountMinor;
  final DateTime date;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String note;

  /// Part of an [TxnType.expense] the owner fronted for others and expects
  /// back. The owner's real cost is `amountMinor - reimbursableMinor`.
  final int reimbursableMinor;

  /// When set on a [TxnType.income], this income is a **repayment** of the
  /// expense with this id — it clears that receivable and is excluded from
  /// regular income totals.
  final String? reimbursesTxnId;

  final DateTime createdAt;

  int get ownShareMinor =>
      type == TxnType.expense ? amountMinor - reimbursableMinor : amountMinor;
  bool get isReimbursement => reimbursesTxnId != null;

  Txn copyWith({
    TxnType? type,
    int? amountMinor,
    DateTime? date,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
    int? reimbursableMinor,
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
    if (reimbursesTxnId != null) 'reimbursesTxnId': reimbursesTxnId,
    'createdAt': createdAt.toIso8601String(),
  };
}
