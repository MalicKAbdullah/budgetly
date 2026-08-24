import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';

class _MemoryVaultFile implements IVaultFile {
  Uint8List? _bytes;

  @override
  Future<Uint8List?> read() async => _bytes;

  @override
  Future<void> write(Uint8List bytes) async => _bytes = bytes;
}

class _MemorySecureStorage implements ISecureStorage {
  final _map = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async =>
      _map[key] = value;

  @override
  Future<String?> read({required String key}) async => _map[key];

  @override
  Future<void> delete({required String key}) async => _map.remove(key);

  @override
  Future<void> deleteAll() async => _map.clear();

  @override
  Future<Map<String, String>> readAll() async => Map.of(_map);
}

void main() {
  /// A container whose vault already holds [seed], loaded and migrated exactly
  /// as the app does on open.
  Future<ProviderContainer> loaded(AppData seed) async {
    final vault = _MemoryVaultFile();
    final storage = _MemorySecureStorage();
    final overrides = [
      vaultFileProvider.overrideWithValue(vault),
      secureStorageProvider.overrideWithValue(storage),
    ];
    final seeding = ProviderContainer(overrides: overrides);
    await seeding.read(budgetlyStoreProvider).save(seed);
    seeding.dispose();

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    await container.read(appDataProvider.future);
    return container;
  }

  AppData read(ProviderContainer c) => c.read(appDataProvider).requireValue;

  test('a vault of typed names is migrated on open', () async {
    final container = await loaded(
      AppData(
        txns: [
          Txn(
            id: 'dinner',
            type: TxnType.expense,
            amountMinor: 6000,
            date: DateTime(2026, 7, 5),
            accountId: 'cash',
            reimbursableMinor: 4000,
            counterparty: 'Ali',
            createdAt: DateTime(2026, 7, 5),
          ),
        ],
      ),
    );
    final data = read(container);
    final ali = data.personByName('Ali')!;
    expect(data.people.length, 1);
    expect(data.txnById('dinner')!.splits.single.personId, ali.id);
    expect(PeopleLedger.forKey(data, ali.id)!.netMinor, 4000);
  });

  test('adding a name that already exists reuses the person', () async {
    final container = await loaded(const AppData());
    final notifier = container.read(appDataProvider.notifier);
    final first = await notifier.addPerson('Ali');
    final again = await notifier.addPerson('  ali ');
    expect(again.id, first.id);
    expect(read(container).people.length, 1);
  });

  test('renaming carries through to the transactions', () async {
    final container = await loaded(
      AppData(
        people: const [Person(id: 'p1', name: 'Ali')],
        txns: [
          Txn(
            id: 'dinner',
            type: TxnType.expense,
            amountMinor: 6000,
            date: DateTime(2026, 7, 5),
            accountId: 'cash',
            reimbursableMinor: 4000,
            counterparty: 'Ali',
            splits: const [TxnSplit(personId: 'p1', amountMinor: 4000)],
            createdAt: DateTime(2026, 7, 5),
          ),
        ],
      ),
    );
    await container.read(appDataProvider.notifier).renamePerson('p1', 'Ali K');
    final data = read(container);
    expect(data.personById('p1')!.name, 'Ali K');
    expect(data.txnById('dinner')!.counterparty, 'Ali K');
    // The money and the reference are untouched by a rename.
    expect(data.txnById('dinner')!.reimbursableMinor, 4000);
    expect(PeopleLedger.forKey(data, 'p1')!.netMinor, 4000);
  });

  test('a person still on a transaction cannot be deleted', () async {
    final container = await loaded(
      AppData(
        people: const [
          Person(id: 'p1', name: 'Ali'),
          Person(id: 'p2', name: 'Sara'),
        ],
        txns: [
          Txn(
            id: 'dinner',
            type: TxnType.expense,
            amountMinor: 6000,
            date: DateTime(2026, 7, 5),
            accountId: 'cash',
            reimbursableMinor: 4000,
            counterparty: 'Ali',
            splits: const [TxnSplit(personId: 'p1', amountMinor: 4000)],
            createdAt: DateTime(2026, 7, 5),
          ),
        ],
      ),
    );
    final notifier = container.read(appDataProvider.notifier);
    expect(await notifier.deletePerson('p1'), isFalse);
    expect(read(container).personById('p1'), isNotNull);
    // Somebody nothing is recorded with goes cleanly.
    expect(await notifier.deletePerson('p2'), isTrue);
    expect(read(container).personById('p2'), isNull);
  });

  test(
    'a settlement recorded from the People screen names its person',
    () async {
      final container = await loaded(
        AppData(
          people: const [Person(id: 'p1', name: 'Ali')],
          txns: [
            Txn(
              id: 'dinner',
              type: TxnType.expense,
              amountMinor: 6000,
              date: DateTime(2026, 7, 5),
              accountId: 'cash',
              reimbursableMinor: 4000,
              counterparty: 'Ali',
              splits: const [TxnSplit(personId: 'p1', amountMinor: 4000)],
              createdAt: DateTime(2026, 7, 5),
            ),
          ],
        ),
      );
      await container
          .read(appDataProvider.notifier)
          .settleWithPerson(
            person: 'Ali',
            personId: 'p1',
            kind: DebtKind.owedToYou,
            amountMinor: 1500,
            accountId: 'cash',
            date: DateTime(2026, 7, 9),
          );
      final data = read(container);
      final settlement = data.txns.firstWhere((t) => t.isSettlement);
      expect(settlement.personId, 'p1');
      expect(PeopleLedger.forKey(data, 'p1')!.netMinor, 2500);
    },
  );
}
