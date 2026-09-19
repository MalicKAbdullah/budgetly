import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/features/statement/statement_pdf_service.dart';

/// The statement is the one place the owner's numbers leave the app, and its
/// savings section was rewritten for the position model. These build every
/// shape that section can take, so a null or a missing field surfaces here
/// rather than when the owner taps Export.
void main() {
  final created = DateTime(2026, 1, 1);
  final now = DateTime(2026, 7, 15);

  Txn txn({
    required String id,
    TxnType type = TxnType.expense,
    required int amountMinor,
    int reimbursableMinor = 0,
    bool settlement = false,
    String accountId = 'bank',
    String? toAccountId,
    String? categoryId,
    String counterparty = '',
    String? personId,
    List<TxnSplit> splits = const [],
    bool receivableCountsAsSavings = false,
    int day = 5,
  }) => Txn(
    id: id,
    type: type,
    amountMinor: amountMinor,
    reimbursableMinor: reimbursableMinor,
    settlement: settlement,
    date: DateTime(2026, 7, day),
    accountId: accountId,
    toAccountId: toAccountId,
    categoryId: categoryId,
    counterparty: counterparty,
    personId: personId,
    splits: splits,
    receivableCountsAsSavings: receivableCountsAsSavings,
    createdAt: created,
  );

  AppData vault({int target = 0, List<Txn> txns = const []}) => AppData(
    accounts: [
      Account(
        id: 'bank',
        name: 'Meezan',
        type: AccountType.bank,
        openingBalanceMinor: 5000000,
        createdAt: created,
      ),
      Account(
        id: 'cash',
        name: 'Cash',
        type: AccountType.cash,
        openingBalanceMinor: 100000,
        createdAt: created,
      ),
    ],
    categories: [Category(id: 'food', name: 'Food', createdAt: created)],
    people: const [Person(id: 'p-ali', name: 'Ali')],
    txns: txns,
    savingsTargetMinor: target,
  );

  Future<void> buildsCleanly(AppData data) async {
    final bytes = await StatementPdfService.build(
      data: data,
      filter: const PeriodFilter.thisMonth(),
      now: now,
    );
    expect(bytes.length, greaterThan(1000));
    // A real PDF, not an empty or truncated document.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  }

  test('a statement with no target builds', () async {
    await buildsCleanly(vault(txns: [txn(id: 'a', amountMinor: 120000)]));
  });

  test('a statement with a target builds', () async {
    await buildsCleanly(
      vault(target: 2000000, txns: [txn(id: 'a', amountMinor: 120000)]),
    );
  });

  test('a statement while dipping into savings builds', () async {
    // Target well above what is held, so free-to-spend is negative.
    await buildsCleanly(
      vault(target: 99000000, txns: [txn(id: 'a', amountMinor: 120000)]),
    );
  });

  test('a statement with counted and uncounted loans builds', () async {
    await buildsCleanly(
      vault(
        target: 1000000,
        txns: [
          txn(
            id: 'lent-counted',
            amountMinor: 300000,
            reimbursableMinor: 300000,
            counterparty: 'Ali',
            splits: const [TxnSplit(personId: 'p-ali', amountMinor: 300000)],
            receivableCountsAsSavings: true,
          ),
          txn(
            id: 'lent-plain',
            amountMinor: 200000,
            reimbursableMinor: 200000,
            counterparty: 'Ali',
            splits: const [TxnSplit(personId: 'p-ali', amountMinor: 200000)],
            day: 6,
          ),
        ],
      ),
    );
  });

  test('a statement covering settlements and transfers builds', () async {
    await buildsCleanly(
      vault(
        txns: [
          txn(
            id: 'move',
            type: TxnType.transfer,
            amountMinor: 50000,
            toAccountId: 'cash',
          ),
          txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 30000,
            settlement: true,
            personId: 'p-ali',
            counterparty: 'Ali',
            day: 7,
          ),
        ],
      ),
    );
  });

  test('an empty vault still produces a statement', () async {
    await buildsCleanly(const AppData());
  });
}
