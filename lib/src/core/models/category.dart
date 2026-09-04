import 'package:flutter/foundation.dart' show immutable;

/// What every transaction in a category does to the savings pot.
///
/// The rule is read live, so setting it counts every transaction in the
/// category — past and future — without rewriting a single record.
enum SavingsEffect {
  none('Not savings'),
  addsToSavings('Adds to savings'),
  takesFromSavings('Takes from savings');

  const SavingsEffect(this.label);
  final String label;

  static SavingsEffect parse(String? raw) => SavingsEffect.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => SavingsEffect.none,
  );
}

/// A spending category with an optional monthly budget (0 = no budget set)
/// and an optional savings rule.
@immutable
final class Category {
  const Category({
    required this.id,
    required this.name,
    this.monthlyBudgetMinor = 0,
    this.savingsEffect = SavingsEffect.none,
    required this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    monthlyBudgetMinor: (json['monthlyBudgetMinor'] as num?)?.toInt() ?? 0,
    savingsEffect: SavingsEffect.parse(json['savingsEffect'] as String?),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String name;
  final int monthlyBudgetMinor;

  /// Whether money on this category is a movement in or out of savings.
  final SavingsEffect savingsEffect;

  final DateTime createdAt;

  bool get hasBudget => monthlyBudgetMinor > 0;

  Category copyWith({
    String? name,
    int? monthlyBudgetMinor,
    SavingsEffect? savingsEffect,
  }) => Category(
    id: id,
    name: name ?? this.name,
    monthlyBudgetMinor: monthlyBudgetMinor ?? this.monthlyBudgetMinor,
    savingsEffect: savingsEffect ?? this.savingsEffect,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'monthlyBudgetMinor': monthlyBudgetMinor,
    if (savingsEffect != SavingsEffect.none)
      'savingsEffect': savingsEffect.name,
    'createdAt': createdAt.toIso8601String(),
  };
}
