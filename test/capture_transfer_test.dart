import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/capture/capture_screen.dart';
import 'package:budgetly/src/features/capture/capture_service.dart';

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

class _NoCaptureService implements CaptureService {
  @override
  bool get supported => true;

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<String>> getPending() async => const [];

  @override
  Future<void> remove(String text) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  final now = DateTime(2026, 8, 20, 14);

  final bank = Account(
    id: 'bank',
    name: 'Meezan',
    type: AccountType.bank,
    createdAt: DateTime(2026),
  );
  final cash = Account(
    id: 'cash',
    name: 'Cash',
    type: AccountType.cash,
    createdAt: DateTime(2026),
  );

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required AppData seed,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
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
        captureServiceProvider.overrideWithValue(_NoCaptureService()),
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

  AppData seedWith(String rawText, {List<Account>? accounts}) => AppData(
    accounts: accounts ?? [bank, cash],
    capturedNotices: [
      CapturedNotice(id: 'n1', rawText: rawText, capturedAt: now),
    ],
  );

  const withdrawal =
      'PKR 20,000.00 has been withdrawn at ATM on 20-Aug-2026 at 13:36 '
      'from your A/C xxx8463 of MEEZAN BANK LIMITED';

  testWidgets('a withdrawal alert opens in Transfer mode and records one', (
    tester,
  ) async {
    final container = await pumpScreen(tester, seed: seedWith(withdrawal));

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();

    // Suggested, and it says why — the user can still override it.
    expect(find.text('Transfer · Rs 20,000'), findsOneWidget);
    expect(find.textContaining('Looks like a cash withdrawal'), findsOneWidget);
    // Transfer shows both ends and no category.
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Category'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add transfer'));
    await tester.pumpAndSettle();

    final data = container.read(appDataProvider).requireValue;
    final txn = data.txns.single;
    expect(txn.type, TxnType.transfer);
    expect(txn.amountMinor, 2000000);
    // Bank out, cash in — the two ends an ATM withdrawal really has.
    expect(txn.accountId, 'bank');
    expect(txn.toAccountId, 'cash');
    expect(txn.categoryId, isNull);
    expect(txn.date, DateTime(2026, 8, 20, 13, 36));
    expect(data.capturedNotices.single.status, CaptureStatus.added);

    container.dispose();
  });

  testWidgets('the same account on both ends is rejected', (tester) async {
    await pumpScreen(tester, seed: seedWith(withdrawal));

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();

    // Point "From" at Cash, which is already the "To" account.
    await tester.tap(
      find.ancestor(
        of: find.text('From account'),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();

    expect(find.text('Pick a different account'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add transfer'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a purchase alert still opens as an expense, overridable', (
    tester,
  ) async {
    final container = await pumpScreen(
      tester,
      seed: seedWith(
        'PKR 1,250.00 has been debited at CHECKOUT MART on 20-Aug-2026 '
        'at 13:36',
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    // Twice: the pending row behind the sheet says the same thing.
    expect(find.text('Expense · Rs 1,250'), findsWidgets);
    expect(find.textContaining('Looks like a cash withdrawal'), findsNothing);
    expect(find.text('To account'), findsNothing);

    // The owner knows it was actually money moved to their wallet.
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    expect(find.text('To account'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add transfer'));
    await tester.pumpAndSettle();

    final txn = container.read(appDataProvider).requireValue.txns.single;
    expect(txn.type, TxnType.transfer);
    expect(txn.accountId, 'bank');
    expect(txn.toAccountId, 'cash');

    container.dispose();
  });
}
