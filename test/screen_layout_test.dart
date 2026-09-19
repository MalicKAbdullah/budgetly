import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/accounts/accounts_screen.dart';
import 'package:budgetly/src/features/budgets/budgets_screen.dart';
import 'package:budgetly/src/features/dashboard/dashboard_screen.dart';
import 'package:budgetly/src/features/people/people_screen.dart';
import 'package:budgetly/src/features/savings/savings_screen.dart';
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

/// Renders every main screen at real phone width, in both themes, with amounts
/// big enough to break a naive layout.
///
/// This is the guard for two bugs the app has actually shipped: a figure wide
/// enough to overflow or truncate its row, and a surface painted the same
/// colour as the text on it.
void main() {
  final created = DateTime(2026, 1, 1);
  final now = DateTime.now();
  DateTime thisMonth(int day) => DateTime(now.year, now.month, day);

  // Six and seven figures: the sizes the owner actually deals in.
  final seed = AppData(
    accounts: [
      Account(
        id: 'bank',
        name: 'Meezan Bank Current Account',
        type: AccountType.bank,
        openingBalanceMinor: 987654321,
        createdAt: created,
      ),
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 12345600,
        createdAt: created,
      ),
    ],
    categories: [
      Category(
        id: 'food',
        name: 'Groceries and household supplies',
        monthlyBudgetMinor: 15000000,
        createdAt: created,
      ),
      Category(id: 'rent', name: 'Rent', createdAt: created),
    ],
    people: const [Person(id: 'p-ali', name: 'Abdul Rahman Khan')],
    txns: [
      Txn(
        id: 'salary',
        type: TxnType.income,
        amountMinor: 45678900,
        date: thisMonth(1),
        accountId: 'bank',
        note: 'Monthly salary',
        createdAt: created,
      ),
      Txn(
        id: 'rent',
        type: TxnType.expense,
        amountMinor: 25000000,
        date: thisMonth(2),
        accountId: 'bank',
        categoryId: 'rent',
        createdAt: created,
      ),
      Txn(
        id: 'shop',
        type: TxnType.expense,
        amountMinor: 1234567,
        date: thisMonth(3),
        accountId: 'cash',
        categoryId: 'food',
        createdAt: created,
      ),
      Txn(
        id: 'lent',
        type: TxnType.expense,
        amountMinor: 5000000,
        reimbursableMinor: 5000000,
        date: thisMonth(4),
        accountId: 'bank',
        categoryId: 'food',
        counterparty: 'Abdul Rahman Khan',
        splits: const [TxnSplit(personId: 'p-ali', amountMinor: 5000000)],
        createdAt: created,
      ),
      Txn(
        id: 'move',
        type: TxnType.transfer,
        amountMinor: 3000000,
        date: thisMonth(5),
        accountId: 'bank',
        toAccountId: 'cash',
        createdAt: created,
      ),
    ],
    savingsTargetMinor: 50000000,
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget screen,
    Brightness brightness,
  ) async {
    // A common small-phone logical size; nothing here may overflow it.
    tester.view.physicalSize = const Size(360, 800);
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
      routes: [GoRoute(path: '/', builder: (_, _) => screen)],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.build(brightness, accent: AppColors.emeraldAccent),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  final screens = <String, Widget Function()>{
    'dashboard': () => const DashboardScreen(),
    'savings': () => const SavingsScreen(),
    'transactions': () => const TransactionsScreen(),
    'accounts': () => const AccountsScreen(),
    'budgets': () => const BudgetsScreen(),
    'people': () => const PeopleScreen(),
  };

  for (final brightness in Brightness.values) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} lays out at 360dp (${brightness.name})', (
        tester,
      ) async {
        await pump(tester, entry.value(), brightness);
        // A RenderFlex overflow is reported as an exception, so this catches
        // every row a long name or a seven-figure amount would break.
        expect(tester.takeException(), isNull);
        // Let the auto-backup debounce fire so no timer outlives the test.
        await tester.pump(const Duration(seconds: 6));
      });

      testWidgets(
        '${entry.key} paints no invisible text (${brightness.name})',
        (tester) async {
          await pump(tester, entry.value(), brightness);
          final background = AppColors.background(brightness);
          final surface = AppColors.surface(brightness);
          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final colour = text.style?.color;
            if (colour == null || (text.data ?? '').isEmpty) continue;
            expect(
              colour,
              isNot(background),
              reason: '"${text.data}" is the page background colour',
            );
            expect(
              colour,
              isNot(surface),
              reason: '"${text.data}" is the card colour it sits on',
            );
          }
          await tester.pump(const Duration(seconds: 6));
        },
      );
    }
  }
}
