import 'package:flutter/foundation.dart' show immutable;

/// The kind of account money sits in. Affects only the icon/label; balances
/// are computed the same way for all.
enum AccountType {
  cash('Cash'),
  bank('Bank'),
  wallet('Wallet'),
  card('Card');

  const AccountType(this.label);
  final String label;

  static AccountType parse(String? raw) => AccountType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => AccountType.cash,
  );
}

/// A place money lives (Cash, a bank account, a mobile wallet…). The live
/// balance is derived from [openingBalanceMinor] plus every transaction that
/// touches it — never stored directly.
@immutable
final class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.openingBalanceMinor = 0,
    this.archived = false,
    required this.createdAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    type: AccountType.parse(json['type'] as String?),
    openingBalanceMinor: (json['openingBalanceMinor'] as num?)?.toInt() ?? 0,
    archived: json['archived'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String name;
  final AccountType type;
  final int openingBalanceMinor;
  final bool archived;
  final DateTime createdAt;

  Account copyWith({
    String? name,
    AccountType? type,
    int? openingBalanceMinor,
    bool? archived,
  }) => Account(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    archived: archived ?? this.archived,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'openingBalanceMinor': openingBalanceMinor,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
  };
}
