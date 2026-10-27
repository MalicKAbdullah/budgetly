import 'dart:math';

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// A heavy owner's vault: [txnCount] transactions spread over the two years
/// before [today], across 6 accounts (one archived), 15 categories (most
/// budgeted) and 10 people, with splits both ways, settlements (some legacy,
/// pointing at the expense they repay), transfers and uncategorized spend.
/// Deterministic for a given [seed].
AppData perfData({required DateTime today, int txnCount = 5000, int seed = 7}) {
  final rng = Random(seed);
  final created = DateTime(today.year - 3);
  final accounts = [
    for (final (i, (name, type)) in const [
      ('Meezan Current', AccountType.bank),
      ('HBL Visa', AccountType.card),
      ('Cash', AccountType.cash),
      ('JazzCash', AccountType.wallet),
      ('UBL Savings', AccountType.bank),
      ('Old wallet', AccountType.wallet),
    ].indexed)
      Account(
        id: 'a$i',
        name: name,
        type: type,
        openingBalanceMinor: rng.nextInt(50000000),
        archived: i == 5,
        createdAt: created,
      ),
  ];
  const categoryNames = [
    'Groceries',
    'Dining out',
    'Transport',
    'Rent',
    'Utilities',
    'Health',
    'Shopping',
    'Entertainment',
    'Education',
    'Gifts',
    'Travel',
    'Phone',
    'Fuel',
    'Charity',
    'Savings',
  ];
  final categories = [
    for (final (i, name) in categoryNames.indexed)
      Category(
        id: 'c$i',
        name: name,
        monthlyBudgetMinor: i % 4 == 3 ? 0 : (i + 1) * 500000,
        createdAt: created,
      ),
  ];
  final people = [
    for (var i = 0; i < 10; i++) Person(id: 'p$i', name: 'Person $i'),
  ];

  DateTime randomDate() {
    final daysAgo = rng.nextInt(730);
    final d = DateTime(today.year, today.month, today.day - daysAgo);
    return DateTime(d.year, d.month, d.day, rng.nextInt(24), rng.nextInt(60));
  }

  final txns = <Txn>[];
  final splitExpenses = <Txn>[];
  for (var i = 0; i < txnCount; i++) {
    final date = randomDate();
    final account = 'a${rng.nextInt(5)}';
    final roll = rng.nextInt(100);
    Txn txn;
    if (roll < 70) {
      txn = Txn(
        id: 't$i',
        type: TxnType.expense,
        amountMinor: 10000 + rng.nextInt(2000000),
        date: date,
        accountId: account,
        categoryId: rng.nextInt(20) == 0
            ? null
            : 'c${rng.nextInt(categories.length)}',
        note: 'Expense $i',
        createdAt: date,
      );
    } else if (roll < 78) {
      final amount = 20000 + rng.nextInt(3000000);
      final share = amount ~/ 2;
      final a = 'p${rng.nextInt(people.length)}';
      final b = 'p${rng.nextInt(people.length)}';
      final receivable = rng.nextBool();
      txn = Txn(
        id: 't$i',
        type: TxnType.expense,
        amountMinor: receivable ? amount : 0,
        reimbursableMinor: receivable ? share : 0,
        payableMinor: receivable ? 0 : share,
        date: date,
        accountId: account,
        categoryId: 'c${rng.nextInt(categories.length)}',
        note: 'Split $i',
        splits: a == b
            ? [TxnSplit(personId: a, amountMinor: share)]
            : [
                TxnSplit(personId: a, amountMinor: share ~/ 2),
                TxnSplit(personId: b, amountMinor: share - share ~/ 2),
              ],
        counterparty: a == b ? 'Person ${a.substring(1)}' : 'Two people',
        receivableCountsAsSavings: receivable && rng.nextInt(3) == 0,
        createdAt: date,
      );
      splitExpenses.add(txn);
    } else if (roll < 88) {
      txn = Txn(
        id: 't$i',
        type: TxnType.income,
        amountMinor: 100000 + rng.nextInt(20000000),
        date: date,
        accountId: account,
        note: 'Income $i',
        createdAt: date,
      );
    } else if (roll < 95) {
      txn = Txn(
        id: 't$i',
        type: TxnType.transfer,
        amountMinor: 50000 + rng.nextInt(5000000),
        date: date,
        accountId: account,
        toAccountId: 'a${rng.nextInt(6)}',
        createdAt: date,
      );
    } else {
      final person = people[rng.nextInt(people.length)];
      final legacyTarget = splitExpenses.isNotEmpty && rng.nextInt(4) == 0
          ? splitExpenses[rng.nextInt(splitExpenses.length)]
          : null;
      final kind = rng.nextBool() ? TxnType.income : TxnType.expense;
      txn = Txn(
        id: 't$i',
        type: kind,
        amountMinor: 10000 + rng.nextInt(1500000),
        date: date,
        accountId: account,
        settlement: legacyTarget == null,
        reimbursesTxnId: legacyTarget?.id,
        personId: legacyTarget == null ? person.id : null,
        counterparty: legacyTarget == null ? person.name : '',
        createdAt: date,
      );
    }
    txns.add(txn);
  }

  return AppData(
    accounts: accounts,
    categories: categories,
    people: people,
    txns: txns,
    savingsTargetMinor: 50000000,
  );
}
