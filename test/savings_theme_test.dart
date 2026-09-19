import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/features/savings/widgets/savings_view.dart';

/// Guards the colour bug this app has already been bitten by twice: a surface
/// painted in the same colour as the text on top of it. Every savings surface
/// is checked in both themes.
void main() {
  final created = DateTime(2026, 1, 1);

  /// Holds Rs 50 against a Rs 80 target, so the owner is Rs 30 short.
  final dipping = AppData(
    accounts: [
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 10000,
        createdAt: created,
      ),
    ],
    txns: [
      Txn(
        id: 'spent',
        type: TxnType.expense,
        amountMinor: 5000,
        date: DateTime(2026, 7, 4),
        accountId: 'cash',
        createdAt: created,
      ),
    ],
    savingsTargetMinor: 8000,
  );

  /// Comfortably above target, so the standing line reads as success.
  final ahead = dipping.copyWith(savingsTargetMinor: 2000);

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  Widget wrap(Brightness brightness, Widget child) => MaterialApp(
    theme: AppTheme.build(brightness, accent: AppColors.emeraldAccent),
    home: Scaffold(body: child),
  );

  for (final brightness in Brightness.values) {
    final name = brightness.name;

    testWidgets('the dip warning is legible on its own surface ($name)', (
      tester,
    ) async {
      final p = Savings.position(dipping);
      expect(p.isDipping, isTrue);

      await tester.pumpWidget(
        wrap(
          brightness,
          SavingsDipWarning(shortfallMinor: -p.freeToSpendMinor, code: 'PKR'),
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

    testWidgets('being short of the target reads as a warning ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          brightness,
          Card(
            child: SavingsProgress(
              position: Savings.position(dipping),
              code: 'PKR',
            ),
          ),
        ),
      );
      final standing = colorOf(tester, 'Rs 30 into your savings');
      expect(standing, AppColors.warning(brightness));
      expect(standing, isNot(AppColors.surface(brightness)));
    });

    testWidgets('being ahead of the target reads as success ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          brightness,
          Card(
            child: SavingsProgress(
              position: Savings.position(ahead),
              code: 'PKR',
            ),
          ),
        ),
      );
      final standing = colorOf(tester, 'Rs 30 free to spend');
      expect(standing, AppColors.success(brightness));
      expect(standing, isNot(AppColors.surface(brightness)));
    });
  }
}
