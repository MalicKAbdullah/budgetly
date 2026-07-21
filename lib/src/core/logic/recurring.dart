import 'package:flutter/foundation.dart' show immutable;
import 'package:tally/src/core/models/recurring_template.dart';
import 'package:tally/src/core/models/txn.dart';

@immutable
final class RecurringRunResult {
  const RecurringRunResult({
    required this.newTxns,
    required this.updatedTemplates,
  });

  final List<Txn> newTxns;
  final List<RecurringTemplate> updatedTemplates;

  bool get hasChanges => newTxns.isNotEmpty;
}

/// Turns due recurring templates into real transactions (with catch-up), and
/// advances each template's next run date. Pure — [now] and [newId] are
/// injected so it is deterministic in tests.
abstract final class RecurringMaterializer {
  static const int maxCatchUpPerTemplate = 60;

  static DateTime advance(RecurringInterval interval, DateTime from) =>
      switch (interval) {
        RecurringInterval.weekly => from.add(const Duration(days: 7)),
        RecurringInterval.monthly => _addMonths(from, 1),
        RecurringInterval.yearly => _addMonths(from, 12),
      };

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute);
  }

  static RecurringRunResult run({
    required List<RecurringTemplate> templates,
    required DateTime now,
    required String Function() newId,
  }) {
    final newTxns = <Txn>[];
    final updated = <RecurringTemplate>[];
    for (final t in templates) {
      if (!t.active) {
        updated.add(t);
        continue;
      }
      var next = t.nextRunDate;
      var guard = 0;
      while (!next.isAfter(now) && guard < maxCatchUpPerTemplate) {
        newTxns.add(
          Txn(
            id: newId(),
            type: t.type,
            amountMinor: t.amountMinor,
            date: next,
            accountId: t.accountId,
            toAccountId: t.toAccountId,
            categoryId: t.categoryId,
            note: t.note,
            createdAt: now,
          ),
        );
        next = advance(t.interval, next);
        guard++;
      }
      updated.add(t.copyWith(nextRunDate: next));
    }
    return RecurringRunResult(newTxns: newTxns, updatedTemplates: updated);
  }
}
