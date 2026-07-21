import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/recurring.dart';
import 'package:budgetly/src/core/logic/reimbursements.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';

void main() {
  final created = DateTime(2026, 1, 1);
  final month = DateTime(2026, 7);

  group('Reimbursements', () {
    // Dinner: paid 6000, but 4000 was fronted for friends (own share 2000).
    final dinner = Txn(
      id: 'dinner',
      type: TxnType.expense,
      amountMinor: 6000,
      reimbursableMinor: 4000,
      date: DateTime(2026, 7, 5),
      accountId: 'cash',
      categoryId: 'food',
      createdAt: created,
    );

    test('own share is what counts as spend', () {
      final data = AppData(txns: [dinner]);
      expect(dinner.ownShareMinor, 2000);
      expect(Budgets.totalSpentInMonthMinor(data, month), 2000);
    });

    test('outstanding is the full reimbursable until repaid', () {
      final data = AppData(txns: [dinner]);
      expect(Reimbursements.totalOwedMinor(data), 4000);
      expect(Reimbursements.outstanding(data).length, 1);
    });

    test('a repayment clears the receivable and is not income', () {
      final repay = Txn(
        id: 'r1',
        type: TxnType.income,
        amountMinor: 4000,
        date: DateTime(2026, 7, 9),
        accountId: 'bank',
        reimbursesTxnId: 'dinner',
        createdAt: created,
      );
      final data = AppData(txns: [dinner, repay]);
      expect(Reimbursements.totalOwedMinor(data), 0);
      expect(Budgets.totalIncomeInMonthMinor(data, month), 0);
    });
  });

  group('RecurringMaterializer', () {
    test('generates due occurrences with catch-up and advances next run', () {
      final template = RecurringTemplate(
        id: 'rent',
        type: TxnType.expense,
        amountMinor: 50000,
        accountId: 'bank',
        categoryId: 'rent',
        interval: RecurringInterval.monthly,
        nextRunDate: DateTime(2026, 5, 1),
        createdAt: created,
      );
      final result = RecurringMaterializer.run(
        templates: [template],
        now: DateTime(2026, 7, 15),
        newId: () => 'id-${DateTime(2026).microsecond}',
      );
      // May, Jun, Jul due → 3 transactions.
      expect(result.newTxns.length, 3);
      expect(result.hasChanges, isTrue);
      // Next run advanced to August.
      expect(result.updatedTemplates.single.nextRunDate, DateTime(2026, 8, 1));
    });

    test('inactive templates produce nothing', () {
      final template = RecurringTemplate(
        id: 'x',
        type: TxnType.income,
        amountMinor: 1,
        accountId: 'bank',
        interval: RecurringInterval.weekly,
        nextRunDate: DateTime(2026, 1, 1),
        active: false,
        createdAt: created,
      );
      final result = RecurringMaterializer.run(
        templates: [template],
        now: DateTime(2026, 7, 1),
        newId: () => 'id',
      );
      expect(result.newTxns, isEmpty);
    });
  });
}
