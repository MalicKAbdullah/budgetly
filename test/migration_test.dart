import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// A vault exactly as v0.10.0 wrote it: no `payableMinor`, no `counterparty`,
/// no `settlement` flag, and a repayment linked with `reimbursesTxnId`.
const _oldVaultJson = '''
{
  "schemaVersion": 3,
  "currencyCode": "PKR",
  "accounts": [
    {
      "id": "cash",
      "name": "Cash",
      "type": "cash",
      "openingBalanceMinor": 100000,
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
    }
  ],
  "txns": [
    {
      "id": "dinner",
      "type": "expense",
      "amountMinor": 6000,
      "date": "2026-07-05T00:00:00.000",
      "accountId": "cash",
      "categoryId": "food",
      "note": "Dinner",
      "reimbursableMinor": 4000,
      "createdAt": "2026-07-05T00:00:00.000"
    },
    {
      "id": "repay1",
      "type": "income",
      "amountMinor": 1500,
      "date": "2026-07-09T00:00:00.000",
      "accountId": "cash",
      "note": "Repayment",
      "reimbursableMinor": 0,
      "reimbursesTxnId": "dinner",
      "createdAt": "2026-07-09T00:00:00.000"
    },
    {
      "id": "salary",
      "type": "income",
      "amountMinor": 50000,
      "date": "2026-07-01T00:00:00.000",
      "accountId": "cash",
      "note": "Salary",
      "reimbursableMinor": 0,
      "createdAt": "2026-07-01T00:00:00.000"
    }
  ],
  "recurringTemplates": [],
  "capturedNotices": []
}
''';

void main() {
  final data = AppData.fromJson(
    jsonDecode(_oldVaultJson) as Map<String, dynamic>,
  );
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final month = DateTime(2026, 7);

  group('An old vault loads unchanged', () {
    test('everything is read back', () {
      expect(data.currencyCode, 'PKR');
      expect(data.accounts.length, 1);
      expect(data.txns.length, 3);
    });

    test('new fields default to "no split, no settlement"', () {
      final salary = data.txnById('salary')!;
      expect(salary.payableMinor, 0);
      expect(salary.counterparty, '');
      expect(salary.settlement, isFalse);
      expect(salary.isSettlement, isFalse);
    });

    test('an existing split expense still costs only the own share', () {
      final dinner = data.txnById('dinner')!;
      expect(dinner.reimbursableMinor, 4000);
      expect(dinner.ownShareMinor, 2000);
      expect(Budgets.totalSpentInMonthMinor(data, month), 2000);
    });

    test('an existing reimbursesTxnId repayment still resolves', () {
      final repay = data.txnById('repay1')!;
      expect(repay.isSettlement, isTrue);
      // 4000 owed, 1500 already repaid.
      expect(PeopleLedger.totalOwedToYouMinor(data), 2500);
      final p = PeopleLedger.forKey(data, '')!;
      expect(p.name, PeopleLedger.unnamedLabel);
      expect(p.entries.single.outstandingMinor, 2500);
    });

    test('the repayment is not income, the salary is', () {
      expect(DashboardFlow.incomeInRange(data, start, end), 50000);
      expect(Budgets.totalIncomeInMonthMinor(data, month), 50000);
    });

    test('the balance still counts every cash movement', () {
      // 100000 opening - 6000 dinner + 1500 repaid + 50000 salary.
      expect(Balances.accountBalanceMinor(data, 'cash'), 145500);
    });
  });

  group('Re-saving an old vault keeps it loadable', () {
    test('a JSON round-trip preserves the legacy fields', () {
      final again = AppData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
      );
      final dinner = again.txnById('dinner')!;
      final repay = again.txnById('repay1')!;
      expect(dinner.reimbursableMinor, 4000);
      expect(repay.reimbursesTxnId, 'dinner');
      expect(PeopleLedger.totalOwedToYouMinor(again), 2500);
    });

    test('untouched transactions do not gain new keys', () {
      final salaryJson = data.txnById('salary')!.toJson();
      expect(salaryJson.containsKey('payableMinor'), isFalse);
      expect(salaryJson.containsKey('counterparty'), isFalse);
      expect(salaryJson.containsKey('settlement'), isFalse);
    });

    test('a new split written today survives a round-trip', () {
      final withSplit = data.copyWith(
        txns: [
          ...data.txns,
          Txn(
            id: 'new-split',
            type: TxnType.expense,
            amountMinor: 0,
            date: DateTime(2026, 7, 20),
            accountId: 'cash',
            payableMinor: 800,
            counterparty: 'Sara',
            createdAt: DateTime(2026, 7, 20),
          ),
        ],
      );
      final again = AppData.fromJson(
        jsonDecode(jsonEncode(withSplit.toJson())) as Map<String, dynamic>,
      );
      expect(PeopleLedger.forKey(again, 'sara')!.netMinor, -800);
      // The legacy person bucket is untouched by the new named one.
      expect(PeopleLedger.forKey(again, '')!.netMinor, 2500);
    });
  });
}
