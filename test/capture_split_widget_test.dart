import 'package:core_ui/core_ui.dart';
import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/capture/capture_screen.dart';
import 'package:budgetly/src/features/capture/capture_service.dart';

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

/// Notification access "granted", with a queue the test controls.
class _FakeCaptureService implements CaptureService {
  _FakeCaptureService(this.queue);

  List<String> queue;
  bool cleared = false;

  @override
  bool get supported => true;

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<String>> getPending() async => queue;

  @override
  Future<void> remove(String text) async => queue.remove(text);

  @override
  Future<void> clear() async {
    cleared = true;
    queue = [];
  }
}

void main() {
  final now = DateTime(2026, 8, 7, 10);

  /// The TextField carrying [label] — labels are unique per field, and the
  /// entered value is not a Text widget, so this is the reliable handle.
  Finder fieldWithLabel(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required AppData seed,
    required CaptureService capture,
  }) async {
    // Tall surface so the whole review sheet is on screen.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final vault = _MemoryVaultFile();
    final storage = _MemorySecureStorage();
    // Seed by writing through the real store, so the screen loads it the same
    // way the app does.
    final seeding = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
        vaultWorkerProvider.overrideWithValue(<R>(work) async => work()),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    await seeding.read(budgetlyStoreProvider).save(seed);
    seeding.dispose();

    final container = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
        vaultWorkerProvider.overrideWithValue(<R>(work) async => work()),
        secureStorageProvider.overrideWithValue(storage),
        captureServiceProvider.overrideWithValue(capture),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CaptureScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  final seed = AppData(
    accounts: [
      Account(
        id: 'bank',
        name: 'Meezan',
        type: AccountType.bank,
        createdAt: DateTime(2026),
      ),
    ],
    categories: [Category(id: 'food', name: 'Food', createdAt: DateTime(2026))],
    people: const [
      Person(id: 'ahmed', name: 'Ahmed'),
      Person(id: 'sara', name: 'Sara'),
    ],
    capturedNotices: [
      CapturedNotice(
        id: 'n1',
        rawText: 'PKR 3,000.00 has been debited at 20:15 on 03-Oct-2026',
        capturedAt: now,
      ),
    ],
  );

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> addPerson(WidgetTester tester, String name) async {
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Add person'));
    await tester.tap(find.widgetWithText(AppListRow, name));
    await tester.pumpAndSettle();
  }

  FilledButton addButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Add split'),
  );

  testWidgets('splits a detected dinner equally with two people', (
    tester,
  ) async {
    final container = await pumpScreen(
      tester,
      seed: seed,
      capture: _FakeCaptureService([]),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();

    // File it under Food, then open the split: the whole payment starts there.
    await tapVisible(
      tester,
      find.ancestor(
        of: find.text('Category'),
        matching: find.byType(AppSelectField<String?>),
      ),
    );
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Split this payment'));
    expect(find.text('Fully assigned.'), findsOneWidget);

    // Adding people with no amounts yet blocks saving.
    await addPerson(tester, 'Ahmed');
    await addPerson(tester, 'Sara');
    expect(
      find.text('Give everyone on the split an amount, or remove them.'),
      findsOneWidget,
    );
    expect(addButton(tester).onPressed, isNull);

    // Typing a part shows the live overshoot against the total.
    await tester.enterText(fieldWithLabel('Ahmed'), '1000');
    await tester.pumpAndSettle();
    expect(find.text('Rs 1,000 over the total.'), findsOneWidget);

    // The preset divides it three ways, the owner's third under Food.
    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Equally, with me'),
    );
    expect(find.text('Fully assigned.'), findsOneWidget);
    expect(find.text('Owed back to you: Rs 2,000'), findsOneWidget);
    expect(addButton(tester).onPressed, isNotNull);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Add split'));

    final data = container.read(appDataProvider).requireValue;
    final txn = data.txns.single;
    expect(txn.type, TxnType.expense);
    expect(txn.amountMinor, 300000);
    expect(txn.categoryId, 'food');
    expect(txn.reimbursableMinor, 200000);
    expect(txn.ownShareMinor, 100000);
    expect(txn.splits.map((s) => (s.personId, s.amountMinor)), [
      ('ahmed', 100000),
      ('sara', 100000),
    ]);
    expect(txn.counterparty, 'Ahmed, Sara');
    expect(data.capturedNotices.single.txnId, txn.id);
    expect(Budgets.spentInMonthMinor(data, 'food', txn.date), 100000);
    expect(PeopleLedger.totalOwedToYouMinor(data), 200000);

    container.dispose();
  });

  testWidgets('percent parts resolve to amounts live', (tester) async {
    final container = await pumpScreen(
      tester,
      seed: seed,
      capture: _FakeCaptureService([]),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Split this payment'));
    await addPerson(tester, 'Ahmed');
    await tapVisible(tester, find.text('Percent'));
    await tester.enterText(fieldWithLabel('Ahmed'), '40');
    await tester.pumpAndSettle();
    expect(find.text('Rs 1,200'), findsOneWidget);
    expect(find.text('Rs 1,200 over the total.'), findsOneWidget);

    // Moving the rest onto the owner's category balances it.
    await tapVisible(tester, find.byTooltip('Put the rest here'));
    expect(find.text('Fully assigned.'), findsOneWidget);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Add split'));

    final txn = container.read(appDataProvider).requireValue.txns.single;
    expect(txn.reimbursableMinor, 120000);
    expect(txn.ownShareMinor, 180000);

    container.dispose();
  });

  testWidgets('a split and a settlement are never combined', (tester) async {
    // Ahmed fronted Rs 500 of the owner's lunch, so a payment out could
    // settle with him.
    final owed = Txn(
      id: 'lunch',
      type: TxnType.expense,
      amountMinor: 0,
      date: DateTime(2026, 9, 1),
      accountId: 'bank',
      payableMinor: 50000,
      splits: const [TxnSplit(personId: 'ahmed', amountMinor: 50000)],
      counterparty: 'Ahmed',
      createdAt: DateTime(2026, 9, 1),
    );
    final container = await pumpScreen(
      tester,
      seed: seed.copyWith(txns: [owed]),
      capture: _FakeCaptureService([]),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('Settles a balance?'), findsOneWidget);

    await tapVisible(tester, find.text('Split this payment'));
    expect(find.text('Settles a balance?'), findsNothing);

    await tapVisible(tester, find.text('Split this payment'));
    expect(find.text('Settles a balance?'), findsOneWidget);

    container.dispose();
  });
}
