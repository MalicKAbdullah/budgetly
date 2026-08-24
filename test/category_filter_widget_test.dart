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
import 'package:budgetly/src/features/transactions/transactions_screen.dart';

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
  // The dashboard resolves the shared window against the real clock and opens
  // on "This month", so the seed lives in the current month.
  final now = DateTime.now();
  DateTime thisMonth(int dayOffset) =>
      DateTime(now.year, now.month, 1).add(Duration(days: dayOffset));

  final bank = Account(
    id: 'bank',
    name: 'Meezan',
    type: AccountType.bank,
    createdAt: thisMonth(0),
  );
  final groceries = Category(
    id: 'food',
    name: 'Groceries',
    createdAt: thisMonth(0),
  );
  final fuel = Category(id: 'fuel', name: 'Fuel', createdAt: thisMonth(0));

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
    categories: [groceries, fuel],
    txns: [
      expense('a', 'food', 300000),
      expense('b', 'food', 100000),
      expense('c', 'fuel', 200000),
      expense('d', null, 50000),
    ],
  );

  Future<void> pumpApp(WidgetTester tester) async {
    // Tall surface so the whole dashboard is laid out.
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

    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
        GoRoute(
          path: '/transactions',
          builder: (_, _) => const TransactionsScreen(),
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

  /// The category row inside the dashboard breakdown (the same name also
  /// appears in the Budgets card, so the finder has to be scoped).
  Finder breakdownRow(String name) => find.descendant(
    of: find.byType(CategoryBreakdown),
    matching: find.text(name),
  );

  testWidgets('tapping a dashboard category lands on a filtered list', (
    tester,
  ) async {
    await pumpApp(tester);

    final row = breakdownRow('Groceries');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    // On the activity list, narrowed to the tapped category…
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.text('2 transactions'), findsOneWidget);
    // …and it says so, so a short list is never a mystery.
    expect(find.text('Category: Groceries'), findsOneWidget);

    // Clearing restores the full list.
    await tester.tap(find.widgetWithText(TextButton, 'Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('4 transactions'), findsOneWidget);
    expect(find.text('Category: Groceries'), findsNothing);
  });

  testWidgets('uncategorized spending is filterable from the dashboard', (
    tester,
  ) async {
    await pumpApp(tester);

    final row = breakdownRow('Uncategorized');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('Category: Uncategorized'), findsOneWidget);
  });

  testWidgets('a filter that matches nothing explains itself', (tester) async {
    await pumpApp(tester);

    final row = breakdownRow('Fuel');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('1 transaction'), findsOneWidget);

    // Combine it with a type that cannot match an expense category.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
    await tester.pumpAndSettle();

    expect(find.text('0 transactions'), findsOneWidget);
    expect(find.text('Nothing to show here'), findsOneWidget);
    expect(find.textContaining('category "Fuel"'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('4 transactions'), findsOneWidget);
  });
}
