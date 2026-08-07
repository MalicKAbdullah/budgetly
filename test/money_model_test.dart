import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/split_text.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/txn.dart';

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
  required TxnType type,
  required int amountMinor,
  required DateTime date,
  String accountId = 'cash',
  int reimbursableMinor = 0,
  int payableMinor = 0,
  String counterparty = '',
  bool settlement = false,
  String? reimbursesTxnId,
}) => Txn(
  id: id,
  type: type,
  amountMinor: amountMinor,
  date: date,
  accountId: accountId,
  reimbursableMinor: reimbursableMinor,
  payableMinor: payableMinor,
  counterparty: counterparty,
  settlement: settlement,
  reimbursesTxnId: reimbursesTxnId,
  createdAt: _created,
);

void main() {
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final month = DateTime(2026, 7);

  group('A settlement is never income and never spending', () {
    // The bug in the owner's own words: pay 1000 with 500 reimbursable, then
    // the friend repays 500. Net must be -500, not 0.
    final bill = _txn(
      id: 'bill',
      type: TxnType.expense,
      amountMinor: 1000,
      date: DateTime(2026, 7, 5),
      reimbursableMinor: 500,
      counterparty: 'Ali',
    );
    final repayment = _txn(
      id: 'repay',
      type: TxnType.income,
      amountMinor: 500,
      date: DateTime(2026, 7, 9),
      counterparty: 'Ali',
      settlement: true,
    );
    final data = AppData(
      accounts: [_account('cash', opening: 10000)],
      txns: [bill, repayment],
    );

    test('spent is the owner share, income excludes the repayment', () {
      expect(DashboardFlow.spentInRange(data, start, end), 500);
      expect(DashboardFlow.incomeInRange(data, start, end), 0);
    });

    test('net is -500 — the owner really is 500 poorer', () {
      final spent = DashboardFlow.spentInRange(data, start, end);
      final income = DashboardFlow.incomeInRange(data, start, end);
      expect(income - spent, -500);
    });

    test('monthly budget roll-ups agree', () {
      expect(Budgets.totalSpentInMonthMinor(data, month), 500);
      expect(Budgets.totalIncomeInMonthMinor(data, month), 0);
    });

    test('the account balance still counts the full cash movement', () {
      // 10000 opening - 1000 paid + 500 received back.
      expect(Balances.accountBalanceMinor(data, 'cash'), 9500);
      final flow = DashboardFlow.byAccount(data, start, end).single;
      expect(flow.outMinor, 1000);
      expect(flow.inMinor, 500);
    });

    test('paying someone back is not an expense either', () {
      final owed = _txn(
        id: 'owed',
        type: TxnType.expense,
        amountMinor: 0,
        date: DateTime(2026, 7, 3),
        payableMinor: 500,
        counterparty: 'Sara',
      );
      final paidBack = _txn(
        id: 'back',
        type: TxnType.expense,
        amountMinor: 500,
        date: DateTime(2026, 7, 20),
        counterparty: 'Sara',
        settlement: true,
      );
      final d = AppData(
        accounts: [_account('cash', opening: 10000)],
        txns: [owed, paidBack],
      );
      // The share is the expense; handing the cash over is not a second one.
      expect(DashboardFlow.spentInRange(d, start, end), 500);
      // Cash really left the account, though.
      expect(Balances.accountBalanceMinor(d, 'cash'), 9500);
    });
  });

  group('Both split directions', () {
    test('receivable: own share is what is left after what is owed back', () {
      final t = _txn(
        id: 'a',
        type: TxnType.expense,
        amountMinor: 1000,
        date: start,
        reimbursableMinor: 500,
      );
      expect(t.ownShareMinor, 500);
    });

    test('payable: the fronted share is still the owner cost', () {
      final t = _txn(
        id: 'b',
        type: TxnType.expense,
        amountMinor: 0,
        date: start,
        payableMinor: 500,
      );
      expect(t.ownShareMinor, 500);
    });

    test('partly fronted: own share is cash out plus what is still owed', () {
      final t = _txn(
        id: 'c',
        type: TxnType.expense,
        amountMinor: 200,
        date: start,
        payableMinor: 300,
      );
      expect(t.ownShareMinor, 500);
    });

    test('the split is spelled out, share first', () {
      final t = _txn(
        id: 'd',
        type: TxnType.expense,
        amountMinor: 100000,
        date: start,
        reimbursableMinor: 50000,
        counterparty: 'Ali',
      );
      expect(
        SplitText.describe(t, 'PKR'),
        'Your share Rs 500 · you paid Rs 1,000 · Rs 500 owed by Ali',
      );
    });
  });

  group('Per-person positions', () {
    final data = AppData(
      accounts: [_account('cash')],
      txns: [
        _txn(
          id: 'a1',
          type: TxnType.expense,
          amountMinor: 2000,
          date: DateTime(2026, 7, 1),
          reimbursableMinor: 1200,
          counterparty: 'Ali',
        ),
        _txn(
          id: 's1',
          type: TxnType.expense,
          amountMinor: 0,
          date: DateTime(2026, 7, 2),
          payableMinor: 300,
          counterparty: 'Sara',
        ),
      ],
    );

    test('nets out per person, each direction', () {
      final ali = PeopleLedger.forKey(data, 'ali')!;
      final sara = PeopleLedger.forKey(data, 'sara')!;
      expect(ali.netMinor, 1200);
      expect(sara.netMinor, -300);
      expect(PeopleLedger.totalOwedToYouMinor(data), 1200);
      expect(PeopleLedger.totalYouOweMinor(data), 300);
    });

    test('names are matched case-insensitively and offered for reuse', () {
      final mixed = AppData(
        txns: [
          ...data.txns,
          _txn(
            id: 'a2',
            type: TxnType.expense,
            amountMinor: 500,
            date: DateTime(2026, 7, 8),
            reimbursableMinor: 500,
            counterparty: 'ALI',
          ),
        ],
      );
      expect(PeopleLedger.forKey(mixed, 'ali')!.netMinor, 1700);
      expect(PeopleLedger.knownNames(mixed), ['Ali', 'Sara']);
    });

    test('unnamed splits collect under one bucket that still settles', () {
      final legacy = AppData(
        txns: [
          _txn(
            id: 'old',
            type: TxnType.expense,
            amountMinor: 900,
            date: DateTime(2026, 7, 4),
            reimbursableMinor: 400,
          ),
        ],
      );
      final p = PeopleLedger.forKey(legacy, '')!;
      expect(p.name, PeopleLedger.unnamedLabel);
      expect(p.netMinor, 400);
    });
  });

  group('Settle allocation is oldest first', () {
    List<Txn> debts() => [
      _txn(
        id: 'old',
        type: TxnType.expense,
        amountMinor: 400,
        date: DateTime(2026, 7, 1),
        reimbursableMinor: 400,
        counterparty: 'Ali',
      ),
      _txn(
        id: 'mid',
        type: TxnType.expense,
        amountMinor: 300,
        date: DateTime(2026, 7, 10),
        reimbursableMinor: 300,
        counterparty: 'Ali',
      ),
      _txn(
        id: 'new',
        type: TxnType.expense,
        amountMinor: 200,
        date: DateTime(2026, 7, 20),
        reimbursableMinor: 200,
        counterparty: 'Ali',
      ),
    ];

    test('a part payment clears the oldest debts first', () {
      final data = AppData(
        txns: [
          ...debts(),
          _txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 500,
            date: DateTime(2026, 7, 25),
            counterparty: 'Ali',
            settlement: true,
          ),
        ],
      );
      final p = PeopleLedger.forKey(data, 'ali')!;
      int open(String id) =>
          p.entries.firstWhere((e) => e.txn.id == id).outstandingMinor;
      expect(open('old'), 0);
      expect(open('mid'), 200);
      expect(open('new'), 200);
      expect(p.netMinor, 400);
    });

    test('a settlement never over-clears', () {
      final data = AppData(
        txns: [
          ...debts(),
          _txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 5000,
            date: DateTime(2026, 7, 25),
            counterparty: 'Ali',
            settlement: true,
          ),
        ],
      );
      expect(PeopleLedger.forKey(data, 'ali')!.netMinor, 0);
    });

    test('a targeted legacy repayment hits its own transaction first', () {
      final data = AppData(
        txns: [
          ...debts(),
          _txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 200,
            date: DateTime(2026, 7, 25),
            reimbursesTxnId: 'new',
          ),
        ],
      );
      final p = PeopleLedger.forKey(data, 'ali')!;
      int open(String id) =>
          p.entries.firstWhere((e) => e.txn.id == id).outstandingMinor;
      expect(open('new'), 0);
      expect(open('old'), 400);
      expect(p.netMinor, 700);
    });

    test('excess from a targeted repayment spills to the oldest debt', () {
      final data = AppData(
        txns: [
          ...debts(),
          _txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 500,
            date: DateTime(2026, 7, 25),
            reimbursesTxnId: 'new',
          ),
        ],
      );
      final p = PeopleLedger.forKey(data, 'ali')!;
      int open(String id) =>
          p.entries.firstWhere((e) => e.txn.id == id).outstandingMinor;
      expect(open('new'), 0);
      expect(open('old'), 100);
      expect(open('mid'), 300);
    });

    test('the two directions are settled independently', () {
      final data = AppData(
        txns: [
          _txn(
            id: 'they-owe',
            type: TxnType.expense,
            amountMinor: 600,
            date: DateTime(2026, 7, 1),
            reimbursableMinor: 600,
            counterparty: 'Ali',
          ),
          _txn(
            id: 'i-owe',
            type: TxnType.expense,
            amountMinor: 0,
            date: DateTime(2026, 7, 2),
            payableMinor: 400,
            counterparty: 'Ali',
          ),
          // Money paid out clears only "you owe them".
          _txn(
            id: 'paid',
            type: TxnType.expense,
            amountMinor: 400,
            date: DateTime(2026, 7, 5),
            counterparty: 'Ali',
            settlement: true,
          ),
        ],
      );
      final p = PeopleLedger.forKey(data, 'ali')!;
      expect(p.youOweMinor, 0);
      expect(p.owedToYouMinor, 600);
    });
  });
}
