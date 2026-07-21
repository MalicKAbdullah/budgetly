import 'package:flutter/foundation.dart' show immutable;

/// A spending category with an optional monthly budget (0 = no budget set).
@immutable
final class Category {
  const Category({
    required this.id,
    required this.name,
    this.monthlyBudgetMinor = 0,
    required this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    monthlyBudgetMinor: (json['monthlyBudgetMinor'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final String id;
  final String name;
  final int monthlyBudgetMinor;
  final DateTime createdAt;

  bool get hasBudget => monthlyBudgetMinor > 0;

  Category copyWith({String? name, int? monthlyBudgetMinor}) => Category(
    id: id,
    name: name ?? this.name,
    monthlyBudgetMinor: monthlyBudgetMinor ?? this.monthlyBudgetMinor,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'monthlyBudgetMinor': monthlyBudgetMinor,
    'createdAt': createdAt.toIso8601String(),
  };
}
