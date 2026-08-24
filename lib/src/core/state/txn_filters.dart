import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// Everything the activity list narrows by, in one pure value so the rules can
/// be tested without a widget.
///
/// All four narrow together (logical AND) on top of the shared date window:
/// a transaction is shown only when it is inside the window **and** matches the
/// type, the account, the category and the search text.
@immutable
final class TxnFilters {
  const TxnFilters({
    this.type,
    this.accountId,
    this.categoryId,
    this.search = '',
  });

  /// `null` shows every type.
  final TxnType? type;

  /// `null` shows every account. An account matches a transfer from either
  /// side, so filtering by Cash still shows money arriving there.
  final String? accountId;

  /// `null` shows every category; `''` shows only uncategorized ones.
  final String? categoryId;

  /// Free text matched against the note, the other person's name, and the
  /// account and category names — whatever the owner is likely to remember.
  final String search;

  bool get filtersCategory => categoryId != null;

  /// Whether anything beyond the date window is narrowing the list. Drives the
  /// "why is this list short" hint and the Clear action.
  bool get isActive =>
      type != null ||
      accountId != null ||
      categoryId != null ||
      search.trim().isNotEmpty;

  TxnFilters copyWith({
    TxnType? type,
    String? accountId,
    String? categoryId,
    String? search,
    bool clearType = false,
    bool clearAccount = false,
    bool clearCategory = false,
  }) => TxnFilters(
    type: clearType ? null : (type ?? this.type),
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    search: search ?? this.search,
  );

  /// The matching transactions inside the inclusive `[start, end]` window,
  /// newest first.
  List<Txn> apply(
    AppData data, {
    required DateTime start,
    required DateTime end,
  }) {
    final needle = search.trim().toLowerCase();
    final matches = data.txns.where((t) {
      if (!DashboardFlow.inRange(t.date, start, end)) return false;
      if (type != null && t.type != type) return false;
      if (accountId != null &&
          t.accountId != accountId &&
          t.toAccountId != accountId) {
        return false;
      }
      if (!_matchesCategory(t)) return false;
      if (needle.isNotEmpty && !_matchesSearch(t, data, needle)) return false;
      return true;
    }).toList();
    matches.sort((a, b) => b.date.compareTo(a.date));
    return matches;
  }

  bool _matchesCategory(Txn t) {
    if (categoryId == null) return true;
    final id = t.categoryId ?? '';
    return id == categoryId;
  }

  bool _matchesSearch(Txn t, AppData data, String needle) {
    final haystack = [
      t.note,
      t.counterparty,
      data.accountById(t.accountId)?.name ?? '',
      data.accountById(t.toAccountId)?.name ?? '',
      data.categoryById(t.categoryId)?.name ?? '',
    ].join(' ').toLowerCase();
    return haystack.contains(needle);
  }
}
