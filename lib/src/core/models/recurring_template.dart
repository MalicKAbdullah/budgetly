import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/models/txn.dart';

enum RecurringInterval {
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly');

  const RecurringInterval(this.label);
  final String label;

  static RecurringInterval parse(String? raw) =>
      RecurringInterval.values.firstWhere(
        (i) => i.name == raw,
        orElse: () => RecurringInterval.monthly,
      );
}

/// A repeating transaction (salary, rent, a subscription). On each app open,
/// due occurrences are materialized into real transactions.
@immutable
final class RecurringTemplate {
  const RecurringTemplate({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    required this.interval,
    required this.nextRunDate,
    this.active = true,
    required this.createdAt,
  });

  factory RecurringTemplate.fromJson(Map<String, dynamic> json) =>
      RecurringTemplate(
        id: json['id'] as String,
        type: TxnType.parse(json['type'] as String?),
        amountMinor: (json['amountMinor'] as num).toInt(),
        accountId: json['accountId'] as String,
        toAccountId: json['toAccountId'] as String?,
        categoryId: json['categoryId'] as String?,
        note: json['note'] as String? ?? '',
        interval: RecurringInterval.parse(json['interval'] as String?),
        nextRunDate: DateTime.parse(json['nextRunDate'] as String),
        active: json['active'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final TxnType type;
  final int amountMinor;
  final String accountId;
  final String? toAccountId;
  final String? categoryId;
  final String note;
  final RecurringInterval interval;
  final DateTime nextRunDate;
  final bool active;
  final DateTime createdAt;

  RecurringTemplate copyWith({
    TxnType? type,
    int? amountMinor,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
    RecurringInterval? interval,
    DateTime? nextRunDate,
    bool? active,
  }) => RecurringTemplate(
    id: id,
    type: type ?? this.type,
    amountMinor: amountMinor ?? this.amountMinor,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId ?? this.toAccountId,
    categoryId: categoryId ?? this.categoryId,
    note: note ?? this.note,
    interval: interval ?? this.interval,
    nextRunDate: nextRunDate ?? this.nextRunDate,
    active: active ?? this.active,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amountMinor': amountMinor,
    'accountId': accountId,
    if (toAccountId != null) 'toAccountId': toAccountId,
    if (categoryId != null) 'categoryId': categoryId,
    'note': note,
    'interval': interval.name,
    'nextRunDate': nextRunDate.toIso8601String(),
    'active': active,
    'createdAt': createdAt.toIso8601String(),
  };
}
