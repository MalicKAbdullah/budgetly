import 'package:flutter/foundation.dart' show immutable;

/// Somebody the owner splits money with.
///
/// A person is a record with a stable [id], so a name can be corrected in one
/// place without touching the transactions that reference it. Names are typed
/// by the owner — nothing is read from the device's contacts.
@immutable
final class Person {
  const Person({required this.id, required this.name});

  factory Person.fromJson(Map<String, dynamic> json) =>
      Person(id: json['id'] as String, name: json['name'] as String? ?? '');

  final String id;
  final String name;

  /// Case-insensitive identity, so "ali" and "Ali" are the same person.
  String get nameKey => name.trim().toLowerCase();

  Person copyWith({String? name}) => Person(id: id, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
