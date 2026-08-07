import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
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
  );

  /// Bumped when a field is added. The read path never branches on it — every
  /// field is optional in [fromJson] — so any older vault still loads.
  static const int schemaVersion = 4;

  final String currencyCode;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Txn> txns;
  final List<RecurringTemplate> recurringTemplates;

  /// Bank/wallet notifications captured on-device, newest last.
  final List<CapturedNotice> capturedNotices;

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
  }) => AppData(
    currencyCode: currencyCode ?? this.currencyCode,
    accounts: accounts ?? this.accounts,
    categories: categories ?? this.categories,
    txns: txns ?? this.txns,
    recurringTemplates: recurringTemplates ?? this.recurringTemplates,
    capturedNotices: capturedNotices ?? this.capturedNotices,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'currencyCode': currencyCode,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'txns': txns.map((t) => t.toJson()).toList(),
    'recurringTemplates': recurringTemplates.map((t) => t.toJson()).toList(),
    'capturedNotices': capturedNotices.map((n) => n.toJson()).toList(),
  };
}
