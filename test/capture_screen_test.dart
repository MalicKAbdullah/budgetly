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
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    await seeding.read(budgetlyStoreProvider).save(seed);
    seeding.dispose();

    final container = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
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

  final account = Account(
    id: 'bank',
    name: 'Meezan',
    type: AccountType.bank,
    createdAt: DateTime(2026),
  );

  testWidgets('reviews a pending notice and adds the transaction', (
    tester,
  ) async {
    final seed = AppData(
      accounts: [account],
      capturedNotices: [
        CapturedNotice(
          id: 'n1',
          rawText:
              'PKR 5,000.00 sent to OSAMA SALEEM from your A/C xxx8463 of '
              'MEEZAN BANK LIMITED on 21-Jul-2026 at 13:36 TID:633782',
          capturedAt: now,
        ),
      ],
    );
    final container = await pumpScreen(
      tester,
      seed: seed,
      capture: _FakeCaptureService([]),
    );

    expect(find.text('Needs review (1)'), findsOneWidget);
    expect(find.text('No history yet'), findsOneWidget);

    // Open the modal review sheet from the pending row.
    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();

    // Detected summary + editable, pre-filled fields.
    expect(find.text('Expense · Rs 5,000'), findsOneWidget);
    expect(find.text('5000'), findsOneWidget);

    // The user corrects the purpose, then adds it.
    await tester.enterText(fieldWithLabel('Purpose / note'), 'Rent share');
    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    await tester.pumpAndSettle();

    final data = container.read(appDataProvider).requireValue;
    final txn = data.txns.single;
    expect(txn.type, TxnType.expense);
    expect(txn.amountMinor, 500000);
    expect(txn.note, 'Rent share');
    expect(txn.accountId, 'bank');
    expect(txn.date, DateTime(2026, 7, 21, 13, 36));

    final notice = data.capturedNotices.single;
    expect(notice.status, CaptureStatus.added);
    expect(notice.txnId, txn.id);

    // The row moved from "Needs review" to history.
    expect(find.text('Needs review'), findsOneWidget);
    expect(find.text('Nothing to review'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);

    container.dispose();
  });

  testWidgets('dismissing keeps the notice in history', (tester) async {
    final seed = AppData(
      accounts: [account],
      capturedNotices: [
        CapturedNotice(
          id: 'n1',
          rawText: 'PKR 45,000.00 has been debited at 18:39 on 19-Jul-2026',
          capturedAt: now,
        ),
      ],
    );
    final container = await pumpScreen(
      tester,
      seed: seed,
      capture: _FakeCaptureService([]),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pumpAndSettle();

    final notice = container
        .read(appDataProvider)
        .requireValue
        .capturedNotices
        .single;
    expect(notice.status, CaptureStatus.dismissed);
    expect(find.text('Dismissed'), findsOneWidget);
    expect(find.text('Add anyway'), findsOneWidget);

    container.dispose();
  });

  testWidgets('an unparseable alert still opens with a manual path', (
    tester,
  ) async {
    final seed = AppData(
      accounts: [account],
      capturedNotices: [
        CapturedNotice(
          id: 'n1',
          rawText: 'Your card was used somewhere, no amount here',
          capturedAt: now,
        ),
      ],
    );
    final container = await pumpScreen(
      tester,
      seed: seed,
      capture: _FakeCaptureService([]),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in this one yourself'), findsOneWidget);

    // Blank amount → the add button is disabled until one is typed.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add transaction'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(fieldWithLabel('Amount'), '320.50');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
    await tester.pumpAndSettle();

    expect(
      container.read(appDataProvider).requireValue.txns.single.amountMinor,
      32050,
    );

    container.dispose();
  });

  testWidgets('opening the screen drains the native queue into history', (
    tester,
  ) async {
    final capture = _FakeCaptureService(['PKR 990.00 received from IMRAN']);
    final container = await pumpScreen(
      tester,
      seed: AppData(accounts: [account]),
      capture: capture,
    );

    final notices = container
        .read(appDataProvider)
        .requireValue
        .capturedNotices;
    expect(notices.single.rawText, 'PKR 990.00 received from IMRAN');
    expect(notices.single.status, CaptureStatus.pending);
    expect(capture.cleared, isTrue);
    expect(container.read(pendingNoticesProvider).length, 1);

    container.dispose();
  });
}
