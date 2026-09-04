import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/category.dart';

/// A vault exactly as v0.12.0 wrote it — the shape on the owner's phone
/// today: schema 5, a people registry, a named split, a settlement, a
/// transfer, a recurring template and capture history. Nothing in it knows
/// anything about savings.
const _v0_12_0VaultJson = '''
{
  "schemaVersion": 5,
  "currencyCode": "PKR",
  "accounts": [
    {
      "id": "cash",
      "name": "Cash",
      "type": "cash",
      "openingBalanceMinor": 100000,
      "archived": false,
      "createdAt": "2026-01-01T00:00:00.000"
    },
    {
      "id": "bank",
      "name": "Meezan",
      "type": "bank",
      "openingBalanceMinor": 500000,
      "archived": false,
      "createdAt": "2026-01-01T00:00:00.000"
    }
  ],
  "categories": [
    {
      "id": "food",
      "name": "Food",
      "monthlyBudgetMinor": 500000,
      "createdAt": "2026-01-01T00:00:00.000"
    },
    {
      "id": "rent",
      "name": "Rent",
      "monthlyBudgetMinor": 0,
      "createdAt": "2026-01-01T00:00:00.000"
    }
  ],
  "txns": [
    {
      "id": "salary",
      "type": "income",
      "amountMinor": 250000,
      "date": "2026-07-01T00:00:00.000",
      "accountId": "bank",
      "note": "Salary",
      "reimbursableMinor": 0,
      "createdAt": "2026-07-01T00:00:00.000"
    },
    {
      "id": "dinner",
      "type": "expense",
      "amountMinor": 6000,
      "date": "2026-07-05T00:00:00.000",
      "accountId": "cash",
      "categoryId": "food",
      "note": "Dinner",
      "reimbursableMinor": 4000,
      "counterparty": "Ali",
      "splits": [{"personId": "p-ali", "amountMinor": 4000}],
      "createdAt": "2026-07-05T00:00:00.000"
    },
    {
      "id": "settle",
      "type": "income",
      "amountMinor": 1500,
      "date": "2026-07-09T00:00:00.000",
      "accountId": "cash",
      "note": "Settlement received",
      "reimbursableMinor": 0,
      "counterparty": "Ali",
      "settlement": true,
      "personId": "p-ali",
      "createdAt": "2026-07-09T00:00:00.000"
    },
    {
      "id": "rent-july",
      "type": "expense",
      "amountMinor": 80000,
      "date": "2026-07-03T00:00:00.000",
      "accountId": "bank",
      "categoryId": "rent",
      "note": "",
      "reimbursableMinor": 0,
      "createdAt": "2026-07-03T00:00:00.000"
    },
    {
      "id": "atm",
      "type": "transfer",
      "amountMinor": 20000,
      "date": "2026-07-06T00:00:00.000",
      "accountId": "bank",
      "toAccountId": "cash",
      "note": "ATM",
      "reimbursableMinor": 0,
      "createdAt": "2026-07-06T00:00:00.000"
    }
  ],
  "recurringTemplates": [
    {
      "id": "r-salary",
      "type": "income",
      "amountMinor": 250000,
      "accountId": "bank",
      "note": "Salary",
      "interval": "monthly",
      "nextRunDate": "2026-08-01T00:00:00.000",
      "active": true,
      "createdAt": "2026-01-01T00:00:00.000"
    }
  ],
  "capturedNotices": [
    {
      "id": "n1",
      "rawText": "Meezan: Rs 800 debited",
      "capturedAt": "2026-07-07T00:00:00.000",
      "status": "dismissed"
    }
  ],
  "people": [{"id": "p-ali", "name": "Ali"}]
}
''';

void main() {
  final data = AppData.fromJson(
    jsonDecode(_v0_12_0VaultJson) as Map<String, dynamic>,
  );
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final month = DateTime(2026, 7);

  group('A v0.12.0 vault loads with identical numbers', () {
    test('everything is read back', () {
      expect(data.accounts.length, 2);
      expect(data.categories.length, 2);
      expect(data.txns.length, 5);
      expect(data.recurringTemplates.length, 1);
      expect(data.capturedNotices.length, 1);
      expect(data.people.single.name, 'Ali');
    });

    test('spend and income are exactly what they were', () {
      // Dinner own share 2000 + rent 80000. The transfer and the settlement
      // are not spending, and never were.
      expect(DashboardFlow.spentInRange(data, start, end), 82000);
      expect(Budgets.totalSpentInMonthMinor(data, month), 82000);
      expect(DashboardFlow.incomeInRange(data, start, end), 250000);
      expect(Budgets.totalIncomeInMonthMinor(data, month), 250000);
      expect(Budgets.spentInMonthMinor(data, 'food', month), 2000);
      expect(Budgets.spentInMonthMinor(data, 'rent', month), 80000);
    });

    test('balances are exactly what they were', () {
      // 100000 - 6000 dinner + 1500 settled + 20000 withdrawn.
      expect(Balances.accountBalanceMinor(data, 'cash'), 115500);
      // 500000 + 250000 salary - 80000 rent - 20000 withdrawn.
      expect(Balances.accountBalanceMinor(data, 'bank'), 650000);
      expect(Balances.netWorthMinor(data), 765500);
    });

    test('the per-person position is exactly what it was', () {
      final ali = PeopleLedger.forKey(data, 'p-ali')!;
      expect(ali.name, 'Ali');
      expect(ali.owedToYouMinor, 2500);
      expect(ali.youOweMinor, 0);
      expect(PeopleLedger.totalOwedToYouMinor(data), 2500);
    });

    test('savings starts at zero with no target', () {
      expect(data.savingsTargetMinor, 0);
      expect(Savings.reservedMinor(data), 0);
      expect(Savings.savedInRangeMinor(data, start, end), 0);
      expect(Savings.movements(data), isEmpty);
      // Nothing is silently earmarked, so everything is free to spend.
      expect(Savings.safeToSpendMinor(data), 765500);
      expect(Savings.isDipping(data), isFalse);
      expect(Savings.varianceMinor(data), 0);
    });

    test('every record inherits, and no category carries a rule', () {
      expect(data.txns.every((t) => t.savingsEffectMinor == null), isTrue);
      expect(
        data.categories.every((c) => c.savingsEffect == SavingsEffect.none),
        isTrue,
      );
      expect(data.recurringTemplates.single.savingsEffectMinor, isNull);
    });
  });

  group('Re-saving a v0.12.0 vault adds nothing to it', () {
    final round = AppData.fromJson(
      jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
    );

    test('untouched records gain no savings keys', () {
      expect(
        data.txnById('salary')!.toJson().containsKey('savingsEffectMinor'),
        isFalse,
      );
      expect(
        data.categories.first.toJson().containsKey('savingsEffect'),
        isFalse,
      );
      expect(
        data.recurringTemplates.single.toJson().containsKey(
          'savingsEffectMinor',
        ),
        isFalse,
      );
      expect(data.toJson().containsKey('savingsTargetMinor'), isFalse);
    });

    test('the schema version is bumped', () {
      expect(data.toJson()['schemaVersion'], 6);
    });

    test('a round-trip keeps every number identical', () {
      expect(DashboardFlow.spentInRange(round, start, end), 82000);
      expect(DashboardFlow.incomeInRange(round, start, end), 250000);
      expect(Balances.netWorthMinor(round), 765500);
      expect(PeopleLedger.forKey(round, 'p-ali')!.owedToYouMinor, 2500);
      expect(Savings.reservedMinor(round), 0);
    });

    test('a savings rule written today survives a round-trip', () {
      final withSavings = data.copyWith(
        savingsTargetMinor: 50000,
        categories: [
          data.categories.first.copyWith(
            savingsEffect: SavingsEffect.addsToSavings,
          ),
          ...data.categories.skip(1),
        ],
      );
      final again = AppData.fromJson(
        jsonDecode(jsonEncode(withSavings.toJson())) as Map<String, dynamic>,
      );
      expect(again.savingsTargetMinor, 50000);
      // The food rule now counts the dinner's own share, retroactively.
      expect(Savings.reservedMinor(again), 2000);
      expect(Savings.varianceMinor(again), -48000);
      // And that money is no longer read as spending.
      expect(DashboardFlow.spentInRange(again, start, end), 80000);
    });
  });
}
