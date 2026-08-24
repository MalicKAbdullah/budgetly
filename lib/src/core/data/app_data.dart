import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// The entire app state as one immutable snapshot — serialized to JSON,
/// encrypted, and written as a single file on every mutation (mirrors the
/// Secure Suite storage pattern).
///
/// Compatibility: fields added later must be optional in [fromJson] with a
/// default, so older vaults and backups keep loading.
@immutable
final class AppData {
  const AppData({
    this.currencyCode = 'PKR',
    this.accounts = const <Account>[],
    this.categories = const <Category>[],
    this.txns = const <Txn>[],
    this.recurringTemplates = const <RecurringTemplate>[],
    this.capturedNotices = const <CapturedNotice>[],
    this.people = const <Person>[],
  });

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
    currencyCode: json['currencyCode'] as String? ?? 'PKR',
    accounts: (json['accounts'] as List<dynamic>? ?? const [])
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList(),
    categories: (json['categories'] as List<dynamic>? ?? const [])
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList(),
    txns: (json['txns'] as List<dynamic>? ?? const [])
        .map((e) => Txn.fromJson(e as Map<String, dynamic>))
        .toList(),
    recurringTemplates:
        (json['recurringTemplates'] as List<dynamic>? ?? const [])
            .map((e) => RecurringTemplate.fromJson(e as Map<String, dynamic>))
            .toList(),
    capturedNotices: (json['capturedNotices'] as List<dynamic>? ?? const [])
        .map((e) => CapturedNotice.fromJson(e as Map<String, dynamic>))
        .toList(),
    people: (json['people'] as List<dynamic>? ?? const [])
        .map((e) => Person.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// Bumped when a field is added. The read path never branches on it — every
  /// field is optional in [fromJson] — so any older vault still loads.
  static const int schemaVersion = 5;

  final String currencyCode;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Txn> txns;
  final List<RecurringTemplate> recurringTemplates;

  /// Bank/wallet notifications captured on-device, newest last.
  final List<CapturedNotice> capturedNotices;

  /// Everybody the owner splits money with, in the order they were added.
  final List<Person> people;

  List<CapturedNotice> get pendingNotices =>
      capturedNotices.where((n) => n.isPending).toList();

  List<Account> get activeAccounts =>
      accounts.where((a) => !a.archived).toList();

  Account? accountById(String? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Person? personById(String? id) {
    if (id == null) return null;
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The registered person with this name, matched case-insensitively.
  Person? personByName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final p in people) {
      if (p.nameKey == key) return p;
    }
    return null;
  }

  /// People sorted for display — alphabetical, case-insensitive.
  List<Person> get peopleByName =>
      [...people]..sort((a, b) => a.nameKey.compareTo(b.nameKey));

  Txn? txnById(String id) {
    for (final t in txns) {
      if (t.id == id) return t;
    }
    return null;
  }

  AppData copyWith({
    String? currencyCode,
    List<Account>? accounts,
    List<Category>? categories,
    List<Txn>? txns,
    List<RecurringTemplate>? recurringTemplates,
    List<CapturedNotice>? capturedNotices,
    List<Person>? people,
  }) => AppData(
    currencyCode: currencyCode ?? this.currencyCode,
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    txns: txns ?? this.txns,
    recurringTemplates: recurringTemplates ?? this.recurringTemplates,
    capturedNotices: capturedNotices ?? this.capturedNotices,
    people: people ?? this.people,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'currencyCode': currencyCode,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'txns': txns.map((t) => t.toJson()).toList(),
    'recurringTemplates': recurringTemplates.map((t) => t.toJson()).toList(),
    'capturedNotices': capturedNotices.map((n) => n.toJson()).toList(),
    'people': people.map((p) => p.toJson()).toList(),
  };
}
