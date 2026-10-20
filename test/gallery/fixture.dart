import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// A believable month for one owner: salary, rent, groceries, a shared
/// dinner, a loan to a friend, transfers, recurring bills and two bank alerts
/// waiting for review. Dates are relative to today so every screen that
/// reads "this month" has data.
AppData galleryData() {
  final now = DateTime.now();
  final created = DateTime(now.year - 1);
  DateTime ago(int days, [int hour = 12, int minute = 0]) {
    final d = now.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  var n = 0;
  Txn spend(
    int rupees,
    String category,
    int days, {
    String account = 'bank',
    String note = '',
    int hour = 12,
  }) => Txn(
    id: 't${n++}',
    type: TxnType.expense,
    amountMinor: rupees * 100,
    date: ago(days, hour),
    accountId: account,
    categoryId: category,
    note: note,
    createdAt: created,
  );

  // Every day of the last six weeks gets some spending so trends have shape.
  final daily = <Txn>[
    for (var d = 0; d < 42; d++) ...[
      spend(
        [650, 1200, 380, 2400, 900, 1750, 520][d % 7],
        d.isEven ? 'dining' : 'groceries',
        d,
        account: d % 3 == 0 ? 'cash' : 'card',
        note: d.isEven ? 'Coffee Lab' : 'Imtiaz Super Market',
        hour: 9 + d % 9,
      ),
      if (d % 4 == 1)
        spend(4200, 'transport', d, account: 'cash', note: 'Fuel', hour: 18),
    ],
  ];

  return AppData(
    accounts: [
      Account(
        id: 'bank',
        name: 'Meezan Current',
        type: AccountType.bank,
        openingBalanceMinor: 42500000,
        createdAt: created,
      ),
      Account(
        id: 'card',
        name: 'HBL Visa',
        type: AccountType.card,
        openingBalanceMinor: 0,
        createdAt: created,
      ),
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 3500000,
        createdAt: created,
      ),
      Account(
        id: 'wallet',
        name: 'JazzCash',
        type: AccountType.wallet,
        openingBalanceMinor: 1250000,
        createdAt: created,
      ),
    ],
    categories: [
      Category(
        id: 'groceries',
        name: 'Groceries',
        monthlyBudgetMinor: 2400000,
        createdAt: created,
      ),
      Category(
        id: 'dining',
        name: 'Dining out',
        monthlyBudgetMinor: 800000,
        createdAt: created,
      ),
      Category(
        id: 'transport',
        name: 'Transport',
        monthlyBudgetMinor: 1500000,
        createdAt: created,
      ),
      Category(
        id: 'rent',
        name: 'Rent',
        monthlyBudgetMinor: 6500000,
        createdAt: created,
      ),
      Category(
        id: 'utilities',
        name: 'Utilities',
        monthlyBudgetMinor: 1200000,
        createdAt: created,
      ),
      Category(id: 'health', name: 'Health', createdAt: created),
      Category(
        id: 'savings',
        name: 'Savings',
        savingsEffect: SavingsEffect.addsToSavings,
        createdAt: created,
      ),
    ],
    people: const [
      Person(id: 'p-ali', name: 'Ali Raza'),
      Person(id: 'p-hina', name: 'Hina Shah'),
      Person(id: 'p-omar', name: 'Omar Farooq'),
    ],
    txns: [
      ...daily,
      Txn(
        id: 'salary',
        type: TxnType.income,
        amountMinor: 18500000,
        date: DateTime(now.year, now.month, 1, 8),
        accountId: 'bank',
        note: 'Salary — Northwind',
        createdAt: created,
      ),
      Txn(
        id: 'salary-prev',
        type: TxnType.income,
        amountMinor: 18500000,
        date: DateTime(now.year, now.month - 1, 1, 8),
        accountId: 'bank',
        note: 'Salary — Northwind',
        createdAt: created,
      ),
      Txn(
        id: 'rent',
        type: TxnType.expense,
        amountMinor: 6500000,
        date: DateTime(now.year, now.month, 2, 10),
        accountId: 'bank',
        categoryId: 'rent',
        note: 'October rent',
        createdAt: created,
      ),
      Txn(
        id: 'electric',
        type: TxnType.expense,
        amountMinor: 1148000,
        date: DateTime(now.year, now.month, 5, 11),
        accountId: 'wallet',
        categoryId: 'utilities',
        note: 'K-Electric',
        createdAt: created,
      ),
      Txn(
        id: 'pharmacy',
        type: TxnType.expense,
        amountMinor: 286000,
        date: ago(3, 19),
        accountId: 'card',
        categoryId: 'health',
        note: 'Dvago pharmacy',
        createdAt: created,
      ),
      Txn(
        id: 'dinner',
        type: TxnType.expense,
        amountMinor: 1260000,
        reimbursableMinor: 840000,
        date: ago(1, 21),
        accountId: 'card',
        categoryId: 'dining',
        note: 'Kolachi dinner',
        splits: const [
          TxnSplit(personId: 'p-ali', amountMinor: 420000),
          TxnSplit(personId: 'p-hina', amountMinor: 420000),
        ],
        createdAt: created,
      ),
      Txn(
        id: 'loan',
        type: TxnType.expense,
        amountMinor: 1500000,
        reimbursableMinor: 1500000,
        date: ago(6, 14),
        accountId: 'bank',
        counterparty: 'Omar Farooq',
        splits: const [TxnSplit(personId: 'p-omar', amountMinor: 1500000)],
        createdAt: created,
      ),
      Txn(
        id: 'to-savings',
        type: TxnType.expense,
        amountMinor: 2500000,
        date: DateTime(now.year, now.month, 1, 9),
        accountId: 'bank',
        categoryId: 'savings',
        note: 'Monthly saving',
        createdAt: created,
      ),
      Txn(
        id: 'atm',
        type: TxnType.transfer,
        amountMinor: 2000000,
        date: ago(2, 17),
        accountId: 'bank',
        toAccountId: 'cash',
        createdAt: created,
      ),
    ],
    recurringTemplates: [
      RecurringTemplate(
        id: 'r-rent',
        type: TxnType.expense,
        amountMinor: 6500000,
        accountId: 'bank',
        categoryId: 'rent',
        note: 'Rent',
        interval: RecurringInterval.monthly,
        nextRunDate: DateTime(now.year, now.month + 1, 2),
        createdAt: created,
      ),
      RecurringTemplate(
        id: 'r-salary',
        type: TxnType.income,
        amountMinor: 18500000,
        accountId: 'bank',
        note: 'Salary — Northwind',
        interval: RecurringInterval.monthly,
        nextRunDate: DateTime(now.year, now.month + 1, 1),
        createdAt: created,
      ),
      RecurringTemplate(
        id: 'r-gym',
        type: TxnType.expense,
        amountMinor: 450000,
        accountId: 'card',
        categoryId: 'health',
        note: 'Gym membership',
        interval: RecurringInterval.monthly,
        nextRunDate: ago(-9),
        active: false,
        createdAt: created,
      ),
    ],
    capturedNotices: [
      CapturedNotice(
        id: 'n1',
        rawText:
            'PKR 4,500.00 sent to ALI RAZA from your A/C xxx8463 of '
            'MEEZAN BANK LIMITED on ${now.day}-Oct-2026 at 13:36 TID:633782',
        capturedAt: ago(0, 13, 36),
      ),
      CapturedNotice(
        id: 'n2',
        rawText:
            'PKR 2,350.00 has been debited at 18:39 on ${now.day}-Oct-2026 '
            'from A/C xxx8463 at IMTIAZ SUPER MARKET',
        capturedAt: ago(0, 18, 39),
      ),
    ],
    savingsTargetMinor: 30000000,
  );
}
