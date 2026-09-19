import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/savings.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

final _created = DateTime(2026, 1, 1);

Account _account(String id, {int opening = 0}) => Account(
  id: id,
  name: id,
  type: AccountType.cash,
  openingBalanceMinor: opening,
  createdAt: _created,
);

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
  String counterparty = '',
  String? personId,
  List<TxnSplit> splits = const [],
  bool receivableCountsAsSavings = false,
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
  counterparty: counterparty,
  personId: personId,
  splits: splits,
  receivableCountsAsSavings: receivableCountsAsSavings,
  createdAt: _created,
);

/// An expense that fronts [lentMinor] for Ali, optionally still counted as the
/// owner's own money.
Txn _loan({
  required String id,
  required int amountMinor,
  required int lentMinor,
  required DateTime date,
  bool counts = false,
}) => _txn(
  id: id,
  amountMinor: amountMinor,
  reimbursableMinor: lentMinor,
  date: date,
  counterparty: 'Ali',
  splits: [TxnSplit(personId: 'p-ali', amountMinor: lentMinor)],
  receivableCountsAsSavings: counts,
);

AppData _vault({
  int opening = 100000,
  int target = 0,
  List<Txn> txns = const [],
}) => AppData(
  accounts: [_account('cash', opening: opening)],
  people: [const Person(id: 'p-ali', name: 'Ali')],
  txns: txns,
  savingsTargetMinor: target,
);

void main() {
  final july = DateTime(2026, 7, 10);
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);

  group('The position is everything the owner holds', () {
    test('with no target, the position is net worth and all of it is free', () {
      final p = Savings.position(_vault());
      expect(p.heldMinor, 100000);
      expect(p.positionMinor, 100000);
      expect(p.freeToSpendMinor, 100000);
      expect(p.hasTarget, isFalse);
      expect(p.isDipping, isFalse);
    });

    test('a target is a floor: free to spend is what is above it', () {
      final p = Savings.position(_vault(target: 30000));
      expect(p.positionMinor, 100000);
      expect(p.freeToSpendMinor, 70000);
      expect(p.isDipping, isFalse);
      expect(p.progress, 1.0);
    });

    test('holding less than the target is dipping, and says by how much', () {
      final p = Savings.position(_vault(opening: 20000, target: 50000));
      expect(p.freeToSpendMinor, -30000);
      expect(p.isDipping, isTrue);
      expect(p.progress, closeTo(0.4, 1e-9));
    });

    test('a negative net worth is reported, never clamped', () {
      final data = _vault(
        opening: 1000,
        txns: [_txn(id: 'big', amountMinor: 9000, date: july)],
      );
      final p = Savings.position(data);
      expect(p.heldMinor, -8000);
      expect(p.positionMinor, -8000);
    });
  });

  group('Money lent out is the owner’s call', () {
    test('a loan is not counted by default — the cash has gone', () {
      final data = _vault(
        txns: [
          _loan(id: 'l', amountMinor: 10000, lentMinor: 10000, date: july),
        ],
      );
      final p = Savings.position(data);
      expect(p.heldMinor, 90000);
      expect(p.countedReceivablesMinor, 0);
      expect(p.uncountedReceivablesMinor, 10000);
      expect(p.positionMinor, 90000);
    });

    test('marking it counted puts the outstanding amount back', () {
      final data = _vault(
        txns: [
          _loan(
            id: 'l',
            amountMinor: 10000,
            lentMinor: 10000,
            date: july,
            counts: true,
          ),
        ],
      );
      final p = Savings.position(data);
      expect(p.heldMinor, 90000);
      expect(p.countedReceivablesMinor, 10000);
      expect(p.uncountedReceivablesMinor, 0);
      // Passing money through changed nothing about what the owner has.
      expect(p.positionMinor, 100000);
    });

    test('repaying a counted loan leaves the position untouched', () {
      final lent = _loan(
        id: 'l',
        amountMinor: 10000,
        lentMinor: 10000,
        date: july,
        counts: true,
      );
      final repaid = _txn(
        id: 's',
        type: TxnType.income,
        amountMinor: 10000,
        date: DateTime(2026, 7, 20),
        settlement: true,
        personId: 'p-ali',
        counterparty: 'Ali',
      );
      final p = Savings.position(_vault(txns: [lent, repaid]));
      expect(p.heldMinor, 100000);
      expect(p.countedReceivablesMinor, 0);
      expect(p.positionMinor, 100000);
    });

    test('repaying an uncounted loan raises the position — it is back', () {
      final lent = _loan(
        id: 'l',
        amountMinor: 10000,
        lentMinor: 10000,
        date: july,
      );
      final before = Savings.position(_vault(txns: [lent]));
      final repaid = _txn(
        id: 's',
        type: TxnType.income,
        amountMinor: 10000,
        date: DateTime(2026, 7, 20),
        settlement: true,
        personId: 'p-ali',
        counterparty: 'Ali',
      );
      final after = Savings.position(_vault(txns: [lent, repaid]));
      expect(before.positionMinor, 90000);
      expect(after.positionMinor, 100000);
    });

    test('only the part still outstanding moves when partly repaid', () {
      final lent = _loan(
        id: 'l',
        amountMinor: 10000,
        lentMinor: 10000,
        date: july,
        counts: true,
      );
      final part = _txn(
        id: 's',
        type: TxnType.income,
        amountMinor: 4000,
        date: DateTime(2026, 7, 20),
        settlement: true,
        personId: 'p-ali',
        counterparty: 'Ali',
      );
      final p = Savings.position(_vault(txns: [lent, part]));
      expect(p.countedReceivablesMinor, 6000);
      expect(p.positionMinor, 100000);
    });
  });

  group('Passing money through never changes the position', () {
    test('a transfer between the owner’s own accounts is neutral', () {
      final data = AppData(
        accounts: [_account('cash', opening: 50000), _account('bank')],
        txns: [
          _txn(
            id: 't',
            type: TxnType.transfer,
            amountMinor: 20000,
            date: july,
            accountId: 'cash',
            toAccountId: 'bank',
          ),
        ],
      );
      expect(Savings.position(data).positionMinor, 50000);
      expect(Balances.netWorthMinor(data), 50000);
    });
  });

  group('A window carries earlier money in', () {
    test('money from before the window shows as carried in, not lost', () {
      final data = _vault(
        opening: 0,
        txns: [
          _txn(
            id: 'june',
            type: TxnType.income,
            amountMinor: 30000,
            date: DateTime(2026, 6, 15),
          ),
          _txn(
            id: 'july',
            type: TxnType.income,
            amountMinor: 20000,
            date: DateTime(2026, 7, 15),
          ),
        ],
      );
      final w = Savings.period(data, start, end);
      expect(w.carriedInMinor, 30000, reason: 'last month is still mine');
      expect(w.changeMinor, 20000);
      expect(w.closingMinor, 50000);
    });

    test('a quiet window still shows everything held', () {
      final data = _vault(
        opening: 0,
        txns: [
          _txn(
            id: 'june',
            type: TxnType.income,
            amountMinor: 30000,
            date: DateTime(2026, 6, 15),
          ),
        ],
      );
      final w = Savings.period(data, start, end);
      expect(w.carriedInMinor, 30000);
      expect(w.changeMinor, 0);
      expect(w.closingMinor, 30000);
    });

    test('the last day of the window counts', () {
      final data = _vault(
        opening: 0,
        txns: [
          _txn(
            id: 'last',
            type: TxnType.income,
            amountMinor: 700,
            date: DateTime(2026, 7, 31, 18, 30),
          ),
        ],
      );
      expect(Savings.period(data, start, end).closingMinor, 700);
    });
  });

  group('Savings never distorts spending or income', () {
    test('a target changes no flow figure at all', () {
      final txns = [
        _txn(
          id: 'salary',
          type: TxnType.income,
          amountMinor: 200000,
          date: july,
        ),
        _txn(id: 'food', amountMinor: 3000, date: july),
      ];
      final without = _vault(txns: txns);
      final with_ = _vault(txns: txns, target: 150000);
      expect(
        DashboardFlow.incomeInRange(with_, start, end),
        DashboardFlow.incomeInRange(without, start, end),
      );
      expect(
        DashboardFlow.spentInRange(with_, start, end),
        DashboardFlow.spentInRange(without, start, end),
      );
      expect(DashboardFlow.incomeInRange(with_, start, end), 200000);
      expect(DashboardFlow.spentInRange(with_, start, end), 3000);
    });
  });

  group('Open loans are listed for the owner to decide on', () {
    test('every open receivable appears, newest first', () {
      final data = _vault(
        txns: [
          _loan(
            id: 'a',
            amountMinor: 1000,
            lentMinor: 1000,
            date: DateTime(2026, 7, 2),
          ),
          _loan(
            id: 'b',
            amountMinor: 2000,
            lentMinor: 2000,
            date: DateTime(2026, 7, 9),
          ),
        ],
      );
      final loans = Savings.openLoans(data);
      expect(loans.map((e) => e.txn.id), ['b', 'a']);
    });

    test('a fully repaid loan drops off the list', () {
      final data = _vault(
        txns: [
          _loan(id: 'a', amountMinor: 1000, lentMinor: 1000, date: july),
          _txn(
            id: 's',
            type: TxnType.income,
            amountMinor: 1000,
            date: DateTime(2026, 7, 20),
            settlement: true,
            personId: 'p-ali',
            counterparty: 'Ali',
          ),
        ],
      );
      expect(Savings.openLoans(data), isEmpty);
    });
  });
}
