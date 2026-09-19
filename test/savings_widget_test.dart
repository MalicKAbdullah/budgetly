import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/dashboard/dashboard_screen.dart';
import 'package:budgetly/src/features/dashboard/widgets/dashboard_cards.dart';
import 'package:budgetly/src/features/dashboard/widgets/savings_card.dart';
import 'package:budgetly/src/features/savings/savings_screen.dart';
import 'package:budgetly/src/features/savings/savings_target_screen.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';
import 'package:budgetly/src/features/transactions/txn_editor_screen.dart';

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
  // The shared window opens on "This month", so the seed lives there.
  final now = DateTime.now();
  DateTime thisMonth(int dayOffset) =>
      DateTime(now.year, now.month, 1).add(Duration(days: dayOffset));

  final bank = Account(
    id: 'bank',
    name: 'Meezan',
    type: AccountType.bank,
    openingBalanceMinor: 10000000,
    createdAt: thisMonth(0),
  );
  final pot = Category(
    id: 'pot',
    name: 'Savings pot',
    savingsEffect: SavingsEffect.addsToSavings,
    createdAt: thisMonth(0),
  );
  final food = Category(id: 'food', name: 'Groceries', createdAt: thisMonth(0));

  Txn expense(String id, String? categoryId, int amount) => Txn(
    id: id,
    type: TxnType.expense,
    amountMinor: amount,
    date: thisMonth(1),
    accountId: 'bank',
    categoryId: categoryId,
    createdAt: thisMonth(1),
  );

  final seed = AppData(
    accounts: [bank],
    categories: [pot, food],
    txns: [expense('put-away', 'pot', 500000), expense('shop', 'food', 300000)],
  );

  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
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

    container = ProviderContainer(
      overrides: [
        vaultFileProvider.overrideWithValue(vault),
        secureStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
        GoRoute(path: '/savings', builder: (_, _) => const SavingsScreen()),
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
  }

  Future<void> openSavings(WidgetTester tester) async {
    final card = find.byType(SavingsCard);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  Finder inCard(String text) =>
      find.descendant(of: find.byType(SavingsCard), matching: find.text(text));

  testWidgets('the dashboard card shows the pot and opens the screen', (
    tester,
  ) async {
    await pumpApp(tester);

    // Rs 100,000 opening less the Rs 8,000 that actually left the account.
    expect(inCard('Holding'), findsWidgets);
    expect(inCard('Rs 92,000'), findsWidgets);
    // Both movements are real spending now — nothing is earmarked away.
    expect(
      find.descendant(
        of: find.byType(SummaryCard),
        matching: find.text('Rs 8,000'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SavingsCard),
        matching: find.textContaining('Set a target'),
      ),
      findsOneWidget,
    );

    await openSavings(tester);
    expect(find.byType(SavingsScreen), findsOneWidget);
    // Carry-over is on the screen, so earlier months can never fall off it.
    expect(find.text('Carried in'), findsOneWidget);
    expect(find.text('At end'), findsOneWidget);
    expect(find.text('Money lent out'), findsOneWidget);
  });

  testWidgets('setting a target shows the +/- against it', (tester) async {
    await pumpApp(tester);
    await openSavings(tester);

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SavingsTargetScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '8000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save target'));
    await tester.pumpAndSettle();
    // Let the auto-backup debounce fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));

    expect(
      container.read(appDataProvider).requireValue.savingsTargetMinor,
      800000,
    );
    expect(
      find.descendant(
        of: find.byType(SavingsProgress),
        matching: find.text('Rs 84,000 free to spend'),
      ),
      findsWidgets,
    );
    expect(find.text('Target Rs 8,000'), findsWidgets);
  });
}
