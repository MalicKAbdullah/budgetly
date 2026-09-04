import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/features/savings/widgets/savings_movement_tile.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Guards the colour bug this app has already been bitten by twice: a surface
/// painted in the same colour as the text on top of it. Every new savings
/// surface is checked in both themes.
void main() {
  final created = DateTime(2026, 1, 1);

  final data = AppData(
    accounts: [
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 1000,
        createdAt: created,
      ),
    ],
    categories: [
      Category(
        id: 'pot',
        name: 'Savings pot',
        savingsEffect: SavingsEffect.addsToSavings,
        createdAt: created,
      ),
    ],
    txns: [
      Txn(
        id: 'put',
        type: TxnType.expense,
        amountMinor: 5000,
        date: DateTime(2026, 7, 4),
        accountId: 'cash',
        categoryId: 'pot',
        createdAt: created,
      ),
    ],
    savingsTargetMinor: 8000,
  );

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  for (final brightness in Brightness.values) {
    final name = brightness.name;

    testWidgets('the dip warning is legible on its own surface ($name)', (
      tester,
    ) async {
      final figures = SavingsFigures.from(data);
      expect(figures.isDipping, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness, accent: AppColors.emeraldAccent),
          home: Scaffold(
            body: SavingsDipWarning(
              shortfallMinor: figures.shortfallMinor,
              code: 'PKR',
            ),
          ),
        ),
      );

      final container = brightness == Brightness.dark
          ? AppColors.warningContainerDark
          : AppColors.warningContainerLight;
      final painted = tester
          .widget<Text>(find.textContaining('into your savings'))
          .style!
          .color!;
      expect(painted, isNot(container));
      expect(painted, AppColors.textPrimary(brightness));
    });

    testWidgets('the target variance is legible on the card ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness, accent: AppColors.emeraldAccent),
          home: Scaffold(
            body: Card(
              child: SavingsProgress(
                figures: SavingsFigures.from(data),
                code: 'PKR',
              ),
            ),
          ),
        ),
      );
      final variance = colorOf(tester, '-Rs 30 short of target');
      expect(variance, AppColors.warning(brightness));
      expect(variance, isNot(AppColors.surface(brightness)));
    });

    testWidgets('a movement row reads in and out differently ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness, accent: AppColors.emeraldAccent),
          home: Scaffold(
            body: Column(
              children: [
                SavingsMovementTile(
                  movement: SavingsMovement(
                    txn: data.txns.single,
                    effectMinor: 5000,
                    fromCategoryRule: true,
                  ),
                  data: data,
                ),
                SavingsMovementTile(
                  movement: SavingsMovement(
                    txn: data.txns.single,
                    effectMinor: -2000,
                    fromCategoryRule: false,
                  ),
                  data: data,
                ),
              ],
            ),
          ),
        ),
      );
      expect(colorOf(tester, '+Rs 50'), AppColors.success(brightness));
      expect(colorOf(tester, '-Rs 20'), AppColors.warning(brightness));
      // The two rows explain themselves differently, so neither is ambiguous.
      expect(find.textContaining('from this category\'s rule'), findsOneWidget);
      expect(
        find.textContaining('earmarked on this transaction'),
        findsOneWidget,
      );
    });
  }
}
