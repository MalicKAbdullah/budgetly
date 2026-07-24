import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/recurring.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:uuid/uuid.dart';

/// Holds the decrypted in-memory snapshot and persists (encrypt + write) after
/// every mutation.
final class AppDataNotifier extends AsyncNotifier<AppData> {
  static const _uuid = Uuid();

  @override
  Future<AppData> build() async {
    ref.onDispose(() => _backupDebounce?.cancel());
    final data = await ref.watch(budgetlyStoreProvider).load();
    // Materialize any due recurring transactions (with catch-up) on open.
    final result = RecurringMaterializer.run(
      templates: data.recurringTemplates,
      now: ref.read(clockProvider)(),
      newId: _uuid.v4,
    );
    if (!result.hasChanges) return data;
    final next = data.copyWith(
      txns: [...data.txns, ...result.newTxns],
      recurringTemplates: result.updatedTemplates,
    );
    await ref.read(budgetlyStoreProvider).save(next);
    return next;
  }

  AppData get _data => state.requireValue;

  Timer? _backupDebounce;

  Future<void> _commit(AppData next) async {
    state = AsyncData<AppData>(next);
    await ref.read(budgetlyStoreProvider).save(next);
    _scheduleAutoBackup();
  }

  /// Auto-backup on change: once edits settle (debounced), write an encrypted
  /// backup — but only when a folder + passphrase are configured. Silent;
  /// failures surface via the Settings backup banner. Same-day backups reuse
  /// one dated file, so frequent edits don't pile up files.
  void _scheduleAutoBackup() {
    _backupDebounce?.cancel();
    _backupDebounce = Timer(const Duration(seconds: 5), () async {
      final service = ref.read(autoBackupServiceProvider);
      final config = await service.loadConfig();
      if (!config.isReady) return;
      await service.backupNow(ref.read(budgetlyBackupProducerProvider));
    });
  }

  // -- Accounts -----------------------------------------------------------

  Future<void> saveAccount(Account account) {
    final exists = _data.accounts.any((a) => a.id == account.id);
    final accounts = exists
        ? [for (final a in _data.accounts) a.id == account.id ? account : a]
        : [..._data.accounts, account];
    return _commit(_data.copyWith(accounts: accounts));
  }

  /// Removes an account and every transaction that touches it (keeping the
  /// data consistent). The UI should prefer archiving when history matters.
  Future<void> deleteAccount(String id) => _commit(
    _data.copyWith(
      accounts: _data.accounts.where((a) => a.id != id).toList(),
      txns: _data.txns
          .where((t) => t.accountId != id && t.toAccountId != id)
          .toList(),
    ),
  );

  // -- Categories ---------------------------------------------------------

  Future<void> saveCategory(Category category) {
    final exists = _data.categories.any((c) => c.id == category.id);
    final categories = exists
        ? [for (final c in _data.categories) c.id == category.id ? category : c]
        : [..._data.categories, category];
    return _commit(_data.copyWith(categories: categories));
  }

  /// Removes a category. Transactions keep their (now dangling) categoryId and
  /// are simply treated as uncategorized in budget roll-ups.
  Future<void> deleteCategory(String id) => _commit(
    _data.copyWith(
      categories: _data.categories.where((c) => c.id != id).toList(),
    ),
  );

  // -- Transactions -------------------------------------------------------

  Future<void> saveTxn(Txn txn) {
    final exists = _data.txns.any((t) => t.id == txn.id);
    final txns = exists
        ? [for (final t in _data.txns) t.id == txn.id ? txn : t]
        : [..._data.txns, txn];
    return _commit(_data.copyWith(txns: txns));
  }

  Future<void> deleteTxn(String id) => _commit(
    _data.copyWith(txns: _data.txns.where((t) => t.id != id).toList()),
  );

  /// Records money received back for a reimbursable expense: an income tagged
  /// to that expense, so it clears the receivable (not counted as income).
  Future<void> markReimbursed(
    String expenseId, {
    required int amountMinor,
    required String accountId,
    required DateTime date,
  }) {
    final txn = Txn(
      id: _uuid.v4(),
      type: TxnType.income,
      amountMinor: amountMinor,
      date: date,
      accountId: accountId,
      note: 'Repayment',
      reimbursesTxnId: expenseId,
      createdAt: DateTime.now(),
    );
    return _commit(_data.copyWith(txns: [..._data.txns, txn]));
  }

  // -- Recurring templates ------------------------------------------------

  /// Upserts a recurring template and immediately materializes anything already
  /// due (e.g. a start date of today).
  Future<void> saveRecurring(RecurringTemplate template) {
    final exists = _data.recurringTemplates.any((t) => t.id == template.id);
    final templates = exists
        ? [
            for (final t in _data.recurringTemplates)
              t.id == template.id ? template : t,
          ]
        : [..._data.recurringTemplates, template];
    final result = RecurringMaterializer.run(
      templates: templates,
      now: ref.read(clockProvider)(),
      newId: _uuid.v4,
    );
    return _commit(
      _data.copyWith(
        txns: [..._data.txns, ...result.newTxns],
        recurringTemplates: result.updatedTemplates,
      ),
    );
  }

  Future<void> deleteRecurring(String id) => _commit(
    _data.copyWith(
      recurringTemplates: _data.recurringTemplates
          .where((t) => t.id != id)
          .toList(),
    ),
  );

  /// Pause/resume. Resuming skips missed occurrences so no surprise catch-up
  /// transactions appear.
  Future<void> setRecurringActive(String id, bool active) {
    final t = _data.recurringTemplates.where((x) => x.id == id).firstOrNull;
    if (t == null) return Future.value();
    var updated = t.copyWith(active: active);
    if (active) {
      final now = ref.read(clockProvider)();
      var next = updated.nextRunDate;
      var guard = 0;
      while (!next.isAfter(now) &&
          guard < RecurringMaterializer.maxCatchUpPerTemplate) {
        next = RecurringMaterializer.advance(updated.interval, next);
        guard++;
      }
      updated = updated.copyWith(nextRunDate: next);
    }
    return _commit(
      _data.copyWith(
        recurringTemplates: [
          for (final x in _data.recurringTemplates) x.id == id ? updated : x,
        ],
      ),
    );
  }

  // -- Backup restore -----------------------------------------------------

  /// Replaces the whole dataset with a decoded backup (Phase 1: replace only).
  Future<void> importBackup(AppData imported) => _commit(imported);
}
