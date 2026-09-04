import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/recurring.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';

final _created = DateTime(2026, 1, 1);

Account _account(String id, {int opening = 0}) => Account(
  id: id,
  name: id,
  type: AccountType.cash,
  openingBalanceMinor: opening,
  createdAt: _created,
);

Category _category(String id, {SavingsEffect effect = SavingsEffect.none}) =>
    Category(id: id, name: id, savingsEffect: effect, createdAt: _created);

Txn _txn({
  required String id,
  TxnType type = TxnType.expense,
  required int amountMinor,
  required DateTime date,
  String accountId = 'cash',
  String? toAccountId,
  String? categoryId,
  int reimbursableMinor = 0,
  bool settlement = false,
  int? savingsEffectMinor,
}) => Txn(
  id: id,
  type: type,
  amountMinor: amountMinor,
  date: date,
  accountId: accountId,
  toAccountId: toAccountId,
  categoryId: categoryId,
  reimbursableMinor: reimbursableMinor,
  settlement: settlement,
  savingsEffectMinor: savingsEffectMinor,
  createdAt: _created,
);

void main() {
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final month = DateTime(2026, 7);

  group('The savings numbers', () {
    // 40000 in the account; 5000 of it deliberately reserved.
    final data = AppData(
      accounts: [_account('cash', opening: 40000)],
      categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
      txns: [
        _txn(
          id: 'reserve',
          amountMinor: 5000,
          date: DateTime(2026, 7, 4),
          categoryId: 'pot',
        ),
      ],
      savingsTargetMinor: 8000,
    );

    test('reserved is a running balance over every transaction', () {
      expect(Savings.reservedMinor(data), 5000);
      // Never period-scoped: a window that excludes it still reports it.
      expect(
        Savings.reservedMinor(
          data.copyWith(savingsTargetMinor: 0),
        ),
        5000,
      );
    });

    test('total money is untouched by the earmark — no cash moved out', () {
      // 40000 opening, minus the 5000 the transaction really paid out.
      expect(Savings.totalMinor(data), 35000);
      expect(Balances.accountBalanceMinor(data, 'cash'), 35000);
    });

    test('safe to spend is total minus reserved', () {
      expect(Savings.safeToSpendMinor(data), 30000);
    });

    test('variance is the +/- against the target', () {
      expect(Savings.varianceMinor(data), -3000);
      expect(
        Savings.varianceMinor(data.copyWith(savingsTargetMinor: 3000)),
        2000,
      );
    });

    test('safe to spend goes negative and says so', () {
      final poor = data.copyWith(
        accounts: [_account('cash', opening: 6000)],
      );
      // 6000 opening - 5000 paid = 1000 left, 5000 reserved.
      expect(Savings.safeToSpendMinor(poor), -4000);
      expect(Savings.isDipping(poor), isTrue);
      expect(Savings.isDipping(data), isFalse);
    });
  });

  group('An earmark is never spending and never income', () {
    // A savings category, a real expense, and a salary that reserves part of
    // itself. Mirrors the settlement case: the money is real, the earmark is
    // only a label on part of it.
    final data = AppData(
      accounts: [_account('cash', opening: 200000)],
      categories: [
        _category('pot', effect: SavingsEffect.addsToSavings),
        _category('food'),
      ],
      txns: [
        _txn(
          id: 'reserve',
          amountMinor: 5000,
          date: DateTime(2026, 7, 4),
          categoryId: 'pot',
        ),
        _txn(
          id: 'dinner',
          amountMinor: 3000,
          date: DateTime(2026, 7, 5),
          categoryId: 'food',
        ),
        _txn(
          id: 'salary',
          type: TxnType.income,
          amountMinor: 100000,
          date: DateTime(2026, 7, 1),
          savingsEffectMinor: 20000,
        ),
      ],
    );

    test('spent leaves the earmarked movement out entirely', () {
      expect(DashboardFlow.spentInRange(data, start, end), 3000);
      expect(Budgets.totalSpentInMonthMinor(data, month), 3000);
    });

    test('income counts only the part that is free to spend', () {
      expect(DashboardFlow.incomeInRange(data, start, end), 80000);
      expect(Budgets.totalIncomeInMonthMinor(data, month), 80000);
    });

    test('the savings category shows zero spend against its budget', () {
      expect(Budgets.spentInMonthMinor(data, 'pot', month), 0);
      final rows = Budgets.byCategory(data, month);
      expect(rows.firstWhere((r) => r.categoryId == 'pot').spentMinor, 0);
      expect(rows.firstWhere((r) => r.categoryId == 'food').spentMinor, 3000);
    });

    test('the category breakdown does not credit it with spending', () {
      final breakdown = DashboardFlow.spendByCategory(data, start, end);
      expect(breakdown.firstWhere((e) => e.key == 'pot').value, 0);
      expect(breakdown.firstWhere((e) => e.key == 'food').value, 3000);
    });

    test('the spend chart bars leave it out too', () {
      final total = DashboardFlow.spendBuckets(
        data,
        start,
        end,
      ).fold(0, (s, b) => s + b.minor);
      expect(total, 3000);
    });

    test('balances still count every penny that really moved', () {
      // 200000 + 100000 salary - 5000 - 3000.
      expect(Balances.accountBalanceMinor(data, 'cash'), 292000);
      expect(Savings.reservedMinor(data), 25000);
    });
  });

  group('The category rule is live and retroactive', () {
    final txns = [
      _txn(
        id: 'a',
        amountMinor: 4000,
        date: DateTime(2026, 7, 2),
        categoryId: 'pot',
      ),
      _txn(
        id: 'b',
        amountMinor: 1000,
        date: DateTime(2026, 6, 2),
        categoryId: 'pot',
      ),
    ];
    final before = AppData(
      accounts: [_account('cash', opening: 50000)],
      categories: [_category('pot')],
      txns: txns,
    );

    test('null inherits, so nothing is reserved before a rule exists', () {
      expect(before.txns.every((t) => t.savingsEffectMinor == null), isTrue);
      expect(Savings.reservedMinor(before), 0);
    });

    test('flipping the rule moves reserved with zero edits to records', () {
      final after = before.copyWith(
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
      );
      // Not one transaction was rewritten…
      expect(identical(after.txns, before.txns), isTrue);
      // …and every one of them, past month included, now counts.
      expect(Savings.reservedMinor(after), 5000);

      final out = before.copyWith(
        categories: [_category('pot', effect: SavingsEffect.takesFromSavings)],
      );
      expect(Savings.reservedMinor(out), -5000);
    });

    test('an explicit 0 survives a rule change on its category', () {
      final data = AppData(
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
        txns: [
          _txn(
            id: 'opted-out',
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            categoryId: 'pot',
            savingsEffectMinor: 0,
          ),
        ],
      );
      expect(Savings.effectFor(data.txns.single, data), 0);
      expect(Savings.reservedMinor(data), 0);
    });

    test('an explicit amount beats the category rule', () {
      final data = AppData(
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
        txns: [
          _txn(
            id: 'partial',
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            categoryId: 'pot',
            savingsEffectMinor: 1500,
          ),
        ],
      );
      expect(Savings.reservedMinor(data), 1500);
    });

    test('a split only ever earmarks the owner own share', () {
      final data = AppData(
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
        txns: [
          _txn(
            id: 'shared',
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            categoryId: 'pot',
            reimbursableMinor: 1000,
          ),
        ],
      );
      expect(Savings.reservedMinor(data), 3000);
    });

    test('a settlement in a savings category reserves nothing', () {
      final data = AppData(
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
        txns: [
          _txn(
            id: 'paid-back',
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            categoryId: 'pot',
            settlement: true,
          ),
        ],
      );
      expect(Savings.reservedMinor(data), 0);
    });
  });

  group('A transfer never moves savings', () {
    test('even when its category carries a rule', () {
      final data = AppData(
        accounts: [_account('cash', opening: 10000), _account('bank')],
        categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
        txns: [
          _txn(
            id: 'move',
            type: TxnType.transfer,
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            accountId: 'cash',
            toAccountId: 'bank',
            categoryId: 'pot',
          ),
        ],
      );
      expect(Savings.effectFor(data.txns.single, data), 0);
      expect(Savings.reservedMinor(data), 0);
    });

    test('and even when an earmark is written on it directly', () {
      final data = AppData(
        accounts: [_account('cash', opening: 10000), _account('bank')],
        txns: [
          _txn(
            id: 'move',
            type: TxnType.transfer,
            amountMinor: 4000,
            date: DateTime(2026, 7, 2),
            accountId: 'cash',
            toAccountId: 'bank',
            savingsEffectMinor: 4000,
          ),
        ],
      );
      expect(Savings.reservedMinor(data), 0);
    });
  });

  group('Recurring templates carry their earmark', () {
    test('the generated transaction gets it as its own override', () {
      final template = RecurringTemplate(
        id: 'salary',
        type: TxnType.income,
        amountMinor: 100000,
        accountId: 'cash',
        note: 'Salary',
        interval: RecurringInterval.monthly,
        nextRunDate: DateTime(2026, 7, 1),
        savingsEffectMinor: 20000,
        createdAt: _created,
      );
      var seq = 0;
      final result = RecurringMaterializer.run(
        templates: [template],
        now: DateTime(2026, 7, 15),
        newId: () => 'gen-${seq++}',
      );
      final generated = result.newTxns.single;
      expect(generated.savingsEffectMinor, 20000);

      final data = AppData(
        accounts: [_account('cash')],
        txns: result.newTxns,
      );
      expect(Savings.reservedMinor(data), 20000);
      // Salary is not in a savings category, and the rest is still income.
      expect(DashboardFlow.incomeInRange(data, start, end), 80000);
    });

    test('no earmark on the template leaves the occurrence inheriting', () {
      final template = RecurringTemplate(
        id: 'rent',
        type: TxnType.expense,
        amountMinor: 50000,
        accountId: 'cash',
        interval: RecurringInterval.monthly,
        nextRunDate: DateTime(2026, 7, 1),
        createdAt: _created,
      );
      final result = RecurringMaterializer.run(
        templates: [template],
        now: DateTime(2026, 7, 15),
        newId: () => 'gen',
      );
      expect(result.newTxns.single.savingsEffectMinor, isNull);
    });
  });

  group('Saved in the selected window', () {
    final data = AppData(
      accounts: [_account('cash', opening: 100000)],
      categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
      txns: [
        _txn(
          id: 'june',
          amountMinor: 1000,
          date: DateTime(2026, 6, 10),
          categoryId: 'pot',
        ),
        _txn(
          id: 'july-in',
          amountMinor: 4000,
          date: DateTime(2026, 7, 10),
          categoryId: 'pot',
        ),
        _txn(
          id: 'july-out',
          type: TxnType.income,
          amountMinor: 1500,
          date: DateTime(2026, 7, 20),
          savingsEffectMinor: -1500,
        ),
      ],
    );

    test('respects the window while reserved stays a running total', () {
      expect(Savings.savedInRangeMinor(data, start, end), 2500);
      expect(
        Savings.savedInRangeMinor(data, DateTime(2026, 6), DateTime(2026, 6, 30)),
        1000,
      );
      expect(Savings.reservedMinor(data), 3500);
    });

    test('movements name the transaction behind each one', () {
      final all = Savings.movements(data);
      expect(all.map((m) => m.txn.id), ['july-out', 'july-in', 'june']);
      expect(all.first.effectMinor, -1500);
      expect(all.first.fromCategoryRule, isFalse);
      expect(all[1].fromCategoryRule, isTrue);

      final inJuly = Savings.movements(data, start: start, end: end);
      expect(inJuly.map((m) => m.txn.id), ['july-out', 'july-in']);
    });
  });

  group('The bulk earmark', () {
    final data = AppData(
      accounts: [_account('cash', opening: 100000)],
      categories: [_category('pot', effect: SavingsEffect.addsToSavings)],
      txns: [
        _txn(id: 'a', amountMinor: 1000, date: DateTime(2026, 7, 1)),
        _txn(id: 'b', amountMinor: 2000, date: DateTime(2026, 7, 2)),
        _txn(
          id: 'c',
          amountMinor: 3000,
          date: DateTime(2026, 7, 3),
          categoryId: 'pot',
        ),
      ],
    );

    test('one commit earmarks a whole selection', () {
      final next = Savings.applied(
        data,
        {'a', 'b'},
        SavingsBulkAction.moveToSavings,
      );
      expect(next.txnById('a')!.savingsEffectMinor, 1000);
      expect(next.txnById('b')!.savingsEffectMinor, 2000);
      // Anything unselected is left exactly as it was.
      expect(next.txnById('c')!.savingsEffectMinor, isNull);
      expect(Savings.reservedMinor(next), 6000);
    });

    test('it can take a selection out of savings', () {
      final next = Savings.applied(
        data,
        {'a'},
        SavingsBulkAction.takeFromSavings,
      );
      expect(next.txnById('a')!.savingsEffectMinor, -1000);
      expect(Savings.reservedMinor(next), 2000);
    });

    test('and reset a selection back to inheriting the category', () {
      final earmarked = Savings.applied(
        data,
        {'a', 'c'},
        SavingsBulkAction.moveToSavings,
      );
      expect(Savings.reservedMinor(earmarked), 4000);

      final reset = Savings.applied(
        earmarked,
        {'a', 'c'},
        SavingsBulkAction.resetToCategory,
      );
      expect(reset.txnById('a')!.savingsEffectMinor, isNull);
      expect(reset.txnById('c')!.savingsEffectMinor, isNull);
      // 'c' is back on its category's rule, 'a' has no rule to inherit.
      expect(Savings.reservedMinor(reset), 3000);
    });
  });
}
