import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/data/people_migration.dart';
import 'package:budgetly/src/core/logic/captures.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/recurring.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
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
    // Register the people the typed names refer to. Idempotent: it returns the
    // same instance once there is nothing left to migrate, so a vault that is
    // already current is never rewritten.
    var next = PeopleMigration.run(data, newId: _uuid.v4);

    // Materialize any due recurring transactions (with catch-up) on open.
    final result = RecurringMaterializer.run(
      templates: data.recurringTemplates,
      now: ref.read(clockProvider)(),
      newId: _uuid.v4,
    );
    if (result.hasChanges) {
      next = next.copyWith(
        txns: [...next.txns, ...result.newTxns],
        recurringTemplates: result.updatedTemplates,
      );
    }

    // Drain whatever the native listener queued while the app was closed.
    final drained = await _drainNativeQueue();
    next = _withDrained(next, drained);

    if (identical(next, data)) return data;
    await ref.read(budgetlyStoreProvider).save(next);
    // Only after the notices are safely persisted — a crash between the two
    // leaves them in the native queue to be drained again, never lost.
    await _clearNativeQueue(drained);
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

  // -- People -------------------------------------------------------------

  /// Adds a person, or returns the existing one when that name is already
  /// registered (case-insensitively) — so the registry never holds two records
  /// for the same person.
  Future<Person> addPerson(String name) async {
    final trimmed = name.trim();
    final existing = _data.personByName(trimmed);
    if (existing != null) return existing;
    final person = Person(id: _uuid.v4(), name: trimmed);
    await _commit(_data.copyWith(people: [..._data.people, person]));
    return person;
  }

  /// Renames a person everywhere at once: the record, plus the denormalized
  /// `counterparty` text on every transaction that references them, so rows and
  /// search show the corrected name without any screen consulting the registry.
  Future<void> renamePerson(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return Future.value();
    final people = [
      for (final p in _data.people) p.id == id ? p.copyWith(name: trimmed) : p,
    ];
    final renamed = _data.copyWith(people: people);
    return _commit(
      renamed.copyWith(
        txns: [
          for (final t in _data.txns)
            if (t.personId == id)
              t.copyWith(counterparty: trimmed)
            else if (t.splits.any((s) => s.personId == id))
              t.copyWith(
                counterparty: PeopleLedger.counterpartyLabel(renamed, t.splits),
              )
            else
              t,
        ],
      ),
    );
  }

  /// Removes a person. Refused while any transaction still references them —
  /// the People screen offers it only when nothing does, so a split can never
  /// end up pointing at a person who no longer exists.
  Future<bool> deletePerson(String id) async {
    if (PeopleLedger.txnCountFor(_data, id) > 0) return false;
    await _commit(
      _data.copyWith(people: _data.people.where((p) => p.id != id).toList()),
    );
    return true;
  }

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

  /// Records a settlement with one person: cash really moves (so balances
  /// change) but it is flagged as a settlement, so it counts as neither income
  /// nor spending. It clears that person's oldest open debts first — see
  /// [PeopleLedger] for the allocation rule.
  Future<void> settleWithPerson({
    required String person,
    required String? personId,
    required DebtKind kind,
    required int amountMinor,
    required String accountId,
    required DateTime date,
  }) {
    final txn = Txn(
      id: _uuid.v4(),
      // Money coming back to the owner clears "they owe you"; money going out
      // clears "you owe them".
      type: kind == DebtKind.owedToYou ? TxnType.income : TxnType.expense,
      amountMinor: amountMinor,
      date: date,
      accountId: accountId,
      counterparty: person,
      personId: personId,
      settlement: true,
      note: kind == DebtKind.owedToYou
          ? 'Settlement received'
          : 'Settlement paid',
      createdAt: ref.read(clockProvider)(),
    );
    return _commit(_data.copyWith(txns: [..._data.txns, txn]));
  }

  // -- Captured notifications ---------------------------------------------

  /// Moves anything the native listener queued into the encrypted history and
  /// clears the native side. Safe to call repeatedly — already-known raw text
  /// is skipped.
  Future<void> ingestNativeQueue() async {
    final drained = await _drainNativeQueue();
    final next = _withDrained(_data, drained);
    if (!identical(next, _data)) await _commit(next);
    await _clearNativeQueue(drained);
  }

  /// Records a reviewed notice as a real transaction, in one write.
  Future<void> addTxnForNotice(Txn txn, String noticeId) => _commit(
    _data.copyWith(
      txns: [..._data.txns, txn],
      capturedNotices: CaptureIngest.withStatus(
        _data.capturedNotices,
        noticeId,
        CaptureStatus.added,
        txnId: txn.id,
      ),
    ),
  );

  /// Keeps the notice in history, marked as not wanted.
  Future<void> dismissNotice(String noticeId) => _commit(
    _data.copyWith(
      capturedNotices: CaptureIngest.withStatus(
        _data.capturedNotices,
        noticeId,
        CaptureStatus.dismissed,
      ),
    ),
  );

  Future<List<String>> _drainNativeQueue() async {
    final capture = ref.read(captureServiceProvider);
    if (!capture.supported || !await capture.isEnabled()) return const [];
    return capture.getPending();
  }

  Future<void> _clearNativeQueue(List<String> drained) async {
    if (drained.isNotEmpty) await ref.read(captureServiceProvider).clear();
  }

  AppData _withDrained(AppData base, List<String> drained) {
    if (drained.isEmpty) return base;
    final notices = CaptureIngest.merge(
      existing: base.capturedNotices,
      rawTexts: drained,
      now: ref.read(clockProvider)(),
      newId: _uuid.v4,
    );
    if (identical(notices, base.capturedNotices)) return base;
    return base.copyWith(capturedNotices: notices);
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
  Future<void> importBackup(AppData imported) =>
      _commit(PeopleMigration.run(imported, newId: _uuid.v4));
}
