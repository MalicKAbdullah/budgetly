import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/budgets.dart';
import 'package:budgetly/src/core/logic/capture_split.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/split_allocation.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/features/capture/split_draft.dart';

void main() {
  group('SplitAllocation', () {
    test('equal parts hand the remainder to the earliest parts', () {
      expect(SplitAllocation.equal(10000, 3), [3334, 3333, 3333]);
      expect(SplitAllocation.equal(10001, 3), [3334, 3334, 3333]);
      expect(SplitAllocation.equal(300000, 3), [100000, 100000, 100000]);
      expect(SplitAllocation.equal(2, 3), [1, 1, 0]);
    });

    test('percentages round by largest remainder and sum to the total', () {
      // 1 minor unit at 33.33 / 33.33 / 33.34 %: only the largest share gets it.
      expect(SplitAllocation.byBasisPoints(1, [3333, 3333, 3334]), [0, 0, 1]);
      // 999 at 50/50: the tie goes to the earlier part.
      expect(SplitAllocation.byBasisPoints(999, [5000, 5000]), [500, 499]);
      for (final total in [1, 7, 999, 12345, 300000]) {
        final parts = SplitAllocation.byBasisPoints(total, [1250, 3333, 5417]);
        expect(parts.fold<int>(0, (s, p) => s + p), total);
      }
    });
  });

  group('CaptureSplitDraft', () {
    CaptureSplitDraft draftFor(List<String> people) {
      final d = CaptureSplitDraft()
        ..start(totalMinor: 300000, categoryId: 'food');
      people.forEach(d.addPerson);
      return d;
    }

    test('equally with me: owner keeps the remainder under the category', () {
      final d = draftFor(['ahmed', 'sara'])
        ..splitEqually(100000, includeMe: true);
      final plan = d.plan(100000);
      expect(plan.people.map((p) => p.amountMinor), [33333, 33333]);
      expect(plan.parts.single.categoryId, 'food');
      expect(plan.parts.single.amountMinor, 33334);
      expect(d.validate(100000), isNull);
    });

    test('equally, just them: nothing is filed as the owner’s spending', () {
      final d = draftFor(['ahmed', 'sara'])
        ..splitEqually(300000, includeMe: false);
      final plan = d.plan(300000);
      expect(plan.people.map((p) => p.amountMinor), [150000, 150000]);
      expect(plan.parts, isEmpty);
      expect(d.validate(300000), isNull);
    });

    test('percent input resolves against the owner’s implied rest', () {
      final d = draftFor(['ahmed', 'sara'])..input = PeopleInput.percent;
      d.people[0].amount.text = '33.33';
      d.people[1].amount.text = '33.33';
      expect(d.peopleMinor(100), [33, 33]);
      d.people[1].amount.text = '70';
      expect(d.validate(100), 'The percentages exceed 100%.');
    });

    test('switching input keeps the same split', () {
      final d = draftFor(['ahmed'])..people[0].amount.text = '750';
      d.setInput(PeopleInput.percent, 300000);
      expect(d.people[0].amount.text, '25');
      d.setInput(PeopleInput.amount, 300000);
      expect(d.people[0].amount.text, '750');
    });

    test('fill rest tops a category up to the total', () {
      final d = draftFor(['ahmed'])
        ..people[0].amount.text = '1000'
        ..categories[0].amount.text = '0'
        ..fillRest(0, 300000);
      expect(d.categories[0].amountMinor, 200000);
      expect(d.plan(300000).remainingMinor, 0);
    });
  });

  group('CaptureSplit.validate', () {
    CaptureSplit split(List<int> people, List<int> parts, {int total = 3000}) =>
        CaptureSplit(
          totalMinor: total,
          people: [
            for (var i = 0; i < people.length; i++)
              TxnSplit(personId: 'p$i', amountMinor: people[i]),
          ],
          parts: [
            for (var i = 0; i < parts.length; i++)
              CategoryPart(categoryId: 'c$i', amountMinor: parts[i]),
          ],
        );

    test('parts must sum to the total exactly', () {
      expect(split([1000, 1000], [1000]).validate(), isNull);
      expect(split([1000, 1000], [900]).validate(), 'Place the rest.');
      expect(split([1000, 1000], [1100]).validate(), 'Over the total.');
    });

    test('rejects blank parts, a no-op split and over-owed people', () {
      expect(split([0], [3000]).validate(), contains('everyone'));
      expect(split([1000], [0, 2000]).validate(), contains('every category'));
      expect(split([], [3000]).validate(), contains('second category'));
      expect(split([4000], [], total: 3000).validate(), contains('owe more'));
      expect(split([1000], []).validate(), contains('category'));
    });
  });

  group('capture → split → ledger', () {
    final now = DateTime(2026, 10, 3, 20);
    final base = Txn(
      id: 'dinner',
      type: TxnType.expense,
      amountMinor: 300000,
      date: now,
      accountId: 'bank',
      categoryId: 'food',
      note: 'Dinner',
      createdAt: now,
    );
    AppData seed(List<Txn> txns) => AppData(
      accounts: [
        Account(
          id: 'bank',
          name: 'Meezan',
          type: AccountType.bank,
          createdAt: DateTime(2026),
        ),
      ],
      categories: [
        Category(id: 'food', name: 'Food', createdAt: DateTime(2026)),
        Category(id: 'fuel', name: 'Fuel', createdAt: DateTime(2026)),
      ],
      people: const [
        Person(id: 'ahmed', name: 'Ahmed'),
        Person(id: 'sara', name: 'Sara'),
      ],
      txns: txns,
    );

    test('Rs 3,000 dinner: 1,000 to Food, 2,000 owed by Ahmed and Sara', () {
      const plan = CaptureSplit(
        totalMinor: 300000,
        people: [
          TxnSplit(personId: 'ahmed', amountMinor: 100000),
          TxnSplit(personId: 'sara', amountMinor: 100000),
        ],
        parts: [CategoryPart(categoryId: 'food', amountMinor: 100000)],
      );
      final names = PeopleLedger.counterpartyLabel(seed(const []), plan.people);
      final txns = plan.toTxns(
        base: base,
        counterparty: names,
        newId: () => 'x',
      );
      final data = seed(txns);

      final t = txns.single;
      expect(t.id, 'dinner');
      expect(t.amountMinor, 300000);
      expect(t.reimbursableMinor, 200000);
      expect(t.ownShareMinor, 100000);
      expect(t.splitsBalanced, isTrue);
      expect(t.counterparty, 'Ahmed, Sara');

      expect(Balances.accountBalanceMinor(data, 'bank'), -300000);
      expect(Budgets.spentInMonthMinor(data, 'food', now), 100000);
      final open = PeopleLedger.openPositions(data);
      expect(
        {for (final p in open) p.name: p.netMinor},
        {'Ahmed': 100000, 'Sara': 100000},
      );
    });

    test('my share across two categories records one txn per category', () {
      const plan = CaptureSplit(
        totalMinor: 300000,
        people: [TxnSplit(personId: 'ahmed', amountMinor: 50000)],
        parts: [
          CategoryPart(categoryId: 'food', amountMinor: 150000),
          CategoryPart(categoryId: 'fuel', amountMinor: 100000),
        ],
      );
      var n = 0;
      final txns = plan.toTxns(
        base: base,
        counterparty: 'Ahmed',
        newId: () => 'extra${n++}',
      );
      final data = seed(txns);

      expect(txns.map((t) => t.id), ['dinner', 'extra0']);
      expect(txns.fold<int>(0, (s, t) => s + t.amountMinor), 300000);
      expect(txns[1].reimbursableMinor, 0);
      expect(txns[1].splits, isEmpty);
      expect(Balances.accountBalanceMinor(data, 'bank'), -300000);
      expect(Budgets.spentInMonthMinor(data, 'food', now), 150000);
      expect(Budgets.spentInMonthMinor(data, 'fuel', now), 100000);
      expect(PeopleLedger.openPositions(data).single.netMinor, 50000);
    });

    test('a bill fronted entirely for others is uncategorized receivable', () {
      const plan = CaptureSplit(
        totalMinor: 300000,
        people: [
          TxnSplit(personId: 'ahmed', amountMinor: 150000),
          TxnSplit(personId: 'sara', amountMinor: 150000),
        ],
        parts: [],
      );
      final t = plan
          .toTxns(base: base, counterparty: 'Ahmed, Sara', newId: () => 'x')
          .single;
      expect(t.categoryId, isNull);
      expect(t.ownShareMinor, 0);
      expect(Budgets.spentInMonthMinor(seed([t]), 'food', now), 0);
    });
  });
}
