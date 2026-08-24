import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/transactions/txn_editor_screen.dart';

/// In-memory stand-ins so the real store/crypto path runs without a device.
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
  /// The TextField carrying [label] — labels are unique per field, and the
  /// entered value is not a Text widget, so this is the reliable handle.
  Finder fieldWithLabel(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  final account = Account(
    id: 'cash',
    name: 'Cash',
    type: AccountType.cash,
    createdAt: DateTime(2026),
  );

  /// A transaction as it exists after upgrading: 900 of a 1200 bill owed back,
  /// all of it on Ali.
  final dinner = Txn(
    id: 'dinner',
    type: TxnType.expense,
    amountMinor: 120000,
    date: DateTime(2026, 7, 5),
    accountId: 'cash',
    note: 'Dinner',
    reimbursableMinor: 90000,
    counterparty: 'Ali',
    splits: const [TxnSplit(personId: 'p1', amountMinor: 90000)],
    createdAt: DateTime(2026, 7, 5),
  );

  final seed = AppData(
    accounts: [account],
    txns: [dinner],
    people: const [
      Person(id: 'p1', name: 'Ali'),
      Person(id: 'p2', name: 'Sara'),
    ],
  );

  Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vault = _MemoryVaultFile();
    final storage = _MemorySecureStorage();
    final seeding = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    await seeding.read(budgetlyStoreProvider).save(seed);
    seeding.dispose();

    final container = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    // The data has to be loaded before the editor reads it in initState.
    await container.read(appDataProvider.future);

    // A two-entry stack, so the editor's "Save" can pop back out of it.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/txn/dinner'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/txn/:id',
          builder: (_, state) =>
              TxnEditorScreen(txnId: state.pathParameters['id']),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('adds a second person to an existing split', (tester) async {
    final container = await pumpEditor(tester);

    // It opens on the split it was saved with.
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(fieldWithLabel('Ali'), findsOneWidget);
    expect(find.text('Fully assigned.'), findsOneWidget);

    // Add Sara from the people already registered.
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sara'));
    await tester.pumpAndSettle();

    // Her slice starts empty, so the split no longer adds up and says so.
    expect(fieldWithLabel('Sara'), findsOneWidget);
    expect(find.text('Give everyone on the split an amount.'), findsOneWidget);

    // Halve it between them.
    await tester.enterText(fieldWithLabel('Ali'), '450');
    await tester.pump();
    await tester.enterText(fieldWithLabel('Sara'), '450');
    await tester.pump();
    expect(find.text('Fully assigned.'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Let the auto-backup debounce fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));

    final saved = container
        .read(appDataProvider)
        .requireValue
        .txnById('dinner')!;
    // The authoritative totals are untouched; only the people changed.
    expect(saved.amountMinor, 120000);
    expect(saved.reimbursableMinor, 90000);
    expect(saved.payableMinor, 0);
    expect(saved.ownShareMinor, 30000);
    expect(saved.splits.length, 2);
    expect(TxnSplit.sumOf(saved.splits), 90000);
    expect(saved.splits.map((s) => s.personId), ['p1', 'p2']);
    expect(saved.splitsBalanced, isTrue);
    // The denormalized name text follows the people on it.
    expect(saved.counterparty, 'Ali, Sara');
  });

  testWidgets('refuses a split that does not add up', (tester) async {
    final container = await pumpEditor(tester);

    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sara'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithLabel('Ali'), '400');
    await tester.pump();
    await tester.enterText(fieldWithLabel('Sara'), '100');
    await tester.pump();
    expect(find.textContaining('still to assign'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Assign the rest'), findsOneWidget);
    final unchanged = container
        .read(appDataProvider)
        .requireValue
        .txnById('dinner')!;
    expect(unchanged.splits.length, 1);
    expect(unchanged.splits.single.amountMinor, 90000);
  });

  testWidgets('splits evenly across everyone on it', (tester) async {
    await pumpEditor(tester);

    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sara'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Split evenly'));
    await tester.pumpAndSettle();

    expect(find.text('Fully assigned.'), findsOneWidget);
    expect(find.text('450'), findsNWidgets(2));
  });
}
