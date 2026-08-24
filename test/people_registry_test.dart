import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/data/people_migration.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// A vault exactly as v0.11.0 wrote it: typed `counterparty` names, a
/// `settlement` flag, a `payableMinor` debt, an unnamed split, and a legacy
/// `reimbursesTxnId` repayment. No `people`, no `splits`.
const _v11VaultJson = '''
{
  "schemaVersion": 4,
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
      "counterparty": "Ali",
      "createdAt": "2026-07-05T00:00:00.000"
    },
    {
      "id": "settle-ali",
      "type": "income",
      "amountMinor": 1500,
      "date": "2026-07-09T00:00:00.000",
      "accountId": "cash",
      "note": "Settlement received",
      "reimbursableMinor": 0,
      "counterparty": "ali",
      "settlement": true,
      "createdAt": "2026-07-09T00:00:00.000"
    },
    {
      "id": "taxi",
      "type": "expense",
      "amountMinor": 0,
      "date": "2026-07-06T00:00:00.000",
      "accountId": "cash",
      "note": "Taxi",
      "reimbursableMinor": 0,
      "payableMinor": 700,
      "counterparty": "Sara",
      "createdAt": "2026-07-06T00:00:00.000"
    },
    {
      "id": "unnamed",
      "type": "expense",
      "amountMinor": 900,
      "date": "2026-07-04T00:00:00.000",
      "accountId": "cash",
      "reimbursableMinor": 400,
      "createdAt": "2026-07-04T00:00:00.000"
    },
    {
      "id": "legacy-repay",
      "type": "income",
      "amountMinor": 100,
      "date": "2026-07-11T00:00:00.000",
      "accountId": "cash",
      "reimbursableMinor": 0,
      "reimbursesTxnId": "unnamed",
      "createdAt": "2026-07-11T00:00:00.000"
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

AppData _v11() =>
    AppData.fromJson(jsonDecode(_v11VaultJson) as Map<String, dynamic>);

/// Deterministic ids, so a fixture can be asserted on.
String Function() _ids() {
  var n = 0;
  return () => 'p${++n}';
}

Txn _split({
  required String id,
  required DateTime date,
  required int amountMinor,
  required int reimbursableMinor,
  List<TxnSplit> splits = const [],
  int payableMinor = 0,
}) => Txn(
  id: id,
  type: TxnType.expense,
  amountMinor: amountMinor,
  date: date,
  accountId: 'cash',
  reimbursableMinor: reimbursableMinor,
  payableMinor: payableMinor,
  splits: splits,
  createdAt: date,
);

void main() {
  final start = DateTime(2026, 7, 1);
  final end = DateTime(2026, 7, 31);
  final month = DateTime(2026, 7);

  group('Person and TxnSplit survive JSON', () {
    test('a person round-trips', () {
      const person = Person(id: 'p1', name: 'Ali');
      final again = Person.fromJson(
        jsonDecode(jsonEncode(person.toJson())) as Map<String, dynamic>,
      );
      expect(again.id, 'p1');
      expect(again.name, 'Ali');
      expect(again.nameKey, 'ali');
    });

    test('a slice round-trips', () {
      const slice = TxnSplit(personId: 'p1', amountMinor: 1250);
      final again = TxnSplit.fromJson(
        jsonDecode(jsonEncode(slice.toJson())) as Map<String, dynamic>,
      );
      expect(again.personId, 'p1');
      expect(again.amountMinor, 1250);
    });

    test('a transaction carries its slices through a round-trip', () {
      final txn = _split(
        id: 't',
        date: DateTime(2026, 7, 1),
        amountMinor: 1000,
        reimbursableMinor: 900,
        splits: const [
          TxnSplit(personId: 'p1', amountMinor: 400),
          TxnSplit(personId: 'p2', amountMinor: 500),
        ],
      );
      final again = Txn.fromJson(
        jsonDecode(jsonEncode(txn.toJson())) as Map<String, dynamic>,
      );
      expect(again.splits.length, 2);
      expect(TxnSplit.sumOf(again.splits), 900);
      expect(again.ownShareMinor, 100);
      expect(again.splitsBalanced, isTrue);
    });

    test('a plain transaction gains no new keys', () {
      final json = _split(
        id: 'plain',
        date: start,
        amountMinor: 500,
        reimbursableMinor: 0,
      ).toJson();
      expect(json.containsKey('splits'), isFalse);
      expect(json.containsKey('personId'), isFalse);
      expect(json.containsKey('payableMinor'), isFalse);
      expect(json.containsKey('counterparty'), isFalse);
    });
  });

  group('The splits invariant', () {
    test('an unnamed split is balanced — nothing is assigned', () {
      final t = _split(
        id: 'u',
        date: start,
        amountMinor: 900,
        reimbursableMinor: 400,
      );
      expect(t.splits, isEmpty);
      expect(t.splitsBalanced, isTrue);
    });

    test('named slices must add up to the receivable exactly', () {
      final good = _split(
        id: 'g',
        date: start,
        amountMinor: 900,
        reimbursableMinor: 400,
        splits: const [
          TxnSplit(personId: 'p1', amountMinor: 250),
          TxnSplit(personId: 'p2', amountMinor: 150),
        ],
      );
      final short = _split(
        id: 's',
        date: start,
        amountMinor: 900,
        reimbursableMinor: 400,
        splits: const [TxnSplit(personId: 'p1', amountMinor: 250)],
      );
      expect(good.splitsBalanced, isTrue);
      expect(short.splitsBalanced, isFalse);
    });

    test('the payable is the total when the owner is the one who owes', () {
      final t = _split(
        id: 'owe',
        date: start,
        amountMinor: 0,
        reimbursableMinor: 0,
        payableMinor: 700,
        splits: const [
          TxnSplit(personId: 'p1', amountMinor: 300),
          TxnSplit(personId: 'p2', amountMinor: 400),
        ],
      );
      expect(t.splitTotalMinor, 700);
      expect(t.splitsAreReceivable, isFalse);
      expect(t.splitsBalanced, isTrue);
      expect(t.ownShareMinor, 700);
    });
  });

  group('A v0.11.0 vault loads and migrates', () {
    test('it loads before any migration, with no people', () {
      final data = _v11();
      expect(data.people, isEmpty);
      expect(data.txns.length, 6);
      expect(data.txnById('dinner')!.splits, isEmpty);
      expect(data.txnById('dinner')!.ownShareMinor, 2000);
    });

    test('each typed name becomes exactly one person', () {
      final migrated = PeopleMigration.run(_v11(), newId: _ids());
      // "Ali" and "ali" are the same person; Sara is the second.
      expect(migrated.people.map((p) => p.name), ['Ali', 'Sara']);
      expect(migrated.personByName('ALI')!.id, 'p1');
    });

    test(
      'a single-name split becomes one person and one slice, same total',
      () {
        final migrated = PeopleMigration.run(_v11(), newId: _ids());
        final dinner = migrated.txnById('dinner')!;
        expect(dinner.reimbursableMinor, 4000);
        expect(dinner.ownShareMinor, 2000);
        expect(dinner.splits.single.personId, 'p1');
        expect(dinner.splits.single.amountMinor, 4000);
        expect(dinner.splitsBalanced, isTrue);
      },
    );

    test('a settlement resolves to exactly one person', () {
      final migrated = PeopleMigration.run(_v11(), newId: _ids());
      expect(migrated.txnById('settle-ali')!.personId, 'p1');
    });

    test('the numbers are identical before and after migrating', () {
      final before = _v11();
      final after = PeopleMigration.run(before, newId: _ids());
      for (final data in [before, after]) {
        expect(Budgets.totalSpentInMonthMinor(data, month), 3200);
        expect(Budgets.totalIncomeInMonthMinor(data, month), 50000);
        expect(DashboardFlow.incomeInRange(data, start, end), 50000);
        expect(Balances.accountBalanceMinor(data, 'cash'), 144700);
        expect(PeopleLedger.totalOwedToYouMinor(data), 2800);
        expect(PeopleLedger.totalYouOweMinor(data), 700);
      }
    });

    test('per-person balances read the same, by name or by person', () {
      final before = _v11();
      final after = PeopleMigration.run(before, newId: _ids());
      // Ali: 4000 owed, 1500 settled.
      expect(PeopleLedger.forKey(before, 'ali')!.netMinor, 2500);
      expect(PeopleLedger.forKey(after, 'p1')!.netMinor, 2500);
      // A key captured before the migration still opens the person.
      expect(PeopleLedger.forKey(after, 'ali')!.netMinor, 2500);
      expect(PeopleLedger.forKey(after, 'p2')!.netMinor, -700);
    });

    test('a legacy reimbursesTxnId repayment still resolves', () {
      final after = PeopleMigration.run(_v11(), newId: _ids());
      final unnamed = PeopleLedger.forKey(after, '')!;
      expect(unnamed.name, PeopleLedger.unnamedLabel);
      // 400 owed on the unnamed split, 100 repaid through the legacy link.
      expect(unnamed.netMinor, 300);
      expect(unnamed.entries.single.settledMinor, 100);
    });

    test('unnamed splits keep their own settleable bucket', () {
      final after = PeopleMigration.run(_v11(), newId: _ids());
      expect(after.txnById('unnamed')!.splits, isEmpty);
      expect(after.txnById('unnamed')!.counterparty, '');
      expect(PeopleLedger.forKey(after, '')!.entries.length, 1);
    });

    test('running it twice changes nothing at all', () {
      final once = PeopleMigration.run(_v11(), newId: _ids());
      final twice = PeopleMigration.run(once, newId: _ids());
      expect(identical(once, twice), isTrue);
    });

    test('a vault with nothing to migrate is not rewritten', () {
      final plain = AppData(
        txns: [
          _split(id: 'x', date: start, amountMinor: 500, reimbursableMinor: 0),
        ],
      );
      expect(identical(PeopleMigration.run(plain, newId: _ids()), plain), true);
    });

    test('a round-trip adds no keys to untouched records', () {
      final after = PeopleMigration.run(_v11(), newId: _ids());
      final salary = after.txnById('salary')!.toJson();
      expect(salary.containsKey('splits'), isFalse);
      expect(salary.containsKey('personId'), isFalse);
      expect(salary.containsKey('counterparty'), isFalse);
      final again = AppData.fromJson(
        jsonDecode(jsonEncode(after.toJson())) as Map<String, dynamic>,
      );
      expect(PeopleLedger.forKey(again, 'p1')!.netMinor, 2500);
      expect(identical(PeopleMigration.run(again, newId: _ids()), again), true);
    });
  });

  group('Multi-person splits', () {
    final ali = const Person(id: 'p1', name: 'Ali');
    final sara = const Person(id: 'p2', name: 'Sara');
    final omar = const Person(id: 'p3', name: 'Omar');

    // One bill, three friends, plus a later bill with Ali only.
    final data = AppData(
      people: [ali, sara, omar],
      txns: [
        _split(
          id: 'bill1',
          date: DateTime(2026, 7, 1),
          amountMinor: 4000,
          reimbursableMinor: 3000,
          splits: const [
            TxnSplit(personId: 'p1', amountMinor: 1000),
            TxnSplit(personId: 'p2', amountMinor: 1000),
            TxnSplit(personId: 'p3', amountMinor: 1000),
          ],
        ),
        _split(
          id: 'bill2',
          date: DateTime(2026, 7, 10),
          amountMinor: 1200,
          reimbursableMinor: 600,
          splits: const [TxnSplit(personId: 'p1', amountMinor: 600)],
        ),
      ],
    );

    test('the owner only ever spends their own share', () {
      expect(data.txnById('bill1')!.ownShareMinor, 1000);
      expect(Budgets.totalSpentInMonthMinor(data, month), 1600);
    });

    test('each person owes their own slice', () {
      expect(PeopleLedger.forKey(data, 'p1')!.netMinor, 1600);
      expect(PeopleLedger.forKey(data, 'p2')!.netMinor, 1000);
      expect(PeopleLedger.forKey(data, 'p3')!.netMinor, 1000);
      expect(PeopleLedger.totalOwedToYouMinor(data), 3600);
    });

    test('one person settling clears their oldest slice first', () {
      final settled = data.copyWith(
        txns: [
          ...data.txns,
          Txn(
            id: 'settle',
            type: TxnType.income,
            amountMinor: 1200,
            date: DateTime(2026, 7, 20),
            accountId: 'cash',
            counterparty: 'Ali',
            personId: 'p1',
            settlement: true,
            createdAt: DateTime(2026, 7, 20),
          ),
        ],
      );
      final aliNow = PeopleLedger.forKey(settled, 'p1')!;
      int open(String id) =>
          aliNow.entries.firstWhere((e) => e.txn.id == id).outstandingMinor;
      expect(open('bill1'), 0);
      expect(open('bill2'), 400);
      expect(aliNow.netMinor, 400);
      // Nobody else is touched by Ali paying up.
      expect(PeopleLedger.forKey(settled, 'p2')!.netMinor, 1000);
      expect(PeopleLedger.forKey(settled, 'p3')!.netMinor, 1000);
      // And the repayment is still not income.
      expect(DashboardFlow.incomeInRange(settled, start, end), 0);
    });

    test('both directions net out per person', () {
      final mixed = data.copyWith(
        txns: [
          ...data.txns,
          _split(
            id: 'sara-fronted',
            date: DateTime(2026, 7, 12),
            amountMinor: 0,
            reimbursableMinor: 0,
            payableMinor: 900,
            splits: const [TxnSplit(personId: 'p2', amountMinor: 900)],
          ),
        ],
      );
      final saraNow = PeopleLedger.forKey(mixed, 'p2')!;
      expect(saraNow.owedToYouMinor, 1000);
      expect(saraNow.youOweMinor, 900);
      expect(saraNow.netMinor, 100);
    });

    test('a registered person with no splits still has a row', () {
      final fresh = AppData(
        people: [const Person(id: 'p9', name: 'Zara')],
      );
      final zara = PeopleLedger.forKey(fresh, 'p9')!;
      expect(zara.name, 'Zara');
      expect(zara.isClear, isTrue);
      expect(PeopleLedger.openPositions(fresh), isEmpty);
    });

    test('a person on a transaction cannot be deleted', () {
      expect(PeopleLedger.txnCountFor(data, 'p1'), 2);
      expect(PeopleLedger.txnCountFor(data, 'p3'), 1);
      final fresh = AppData(
        people: [const Person(id: 'p9', name: 'Zara')],
      );
      expect(PeopleLedger.txnCountFor(fresh, 'p9'), 0);
    });

    test('names offered for reuse include registered people', () {
      expect(PeopleLedger.knownNames(data), ['Ali', 'Omar', 'Sara']);
      expect(
        PeopleLedger.counterpartyLabel(data, data.txnById('bill1')!.splits),
        'Ali, Sara, Omar',
      );
    });
  });
}
