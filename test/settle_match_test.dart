import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/logic/settle_match.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';

/// A split the owner fronted ([owedToYou]) or someone fronted for them.
Txn _split(String id, String personId, int minor, {bool owedToYou = true}) =>
    Txn(
      id: id,
      type: TxnType.expense,
      amountMinor: owedToYou ? minor : 0,
      date: DateTime(2026, 9, 1),
      accountId: 'bank',
      reimbursableMinor: owedToYou ? minor : 0,
      payableMinor: owedToYou ? 0 : minor,
      splits: [TxnSplit(personId: personId, amountMinor: minor)],
      createdAt: DateTime(2026, 9, 1),
    );

Txn _detected(TxnType type, int minor, {String note = '', String? cat}) => Txn(
  id: 'new',
  type: type,
  amountMinor: minor,
  date: DateTime(2026, 9, 20),
  accountId: 'bank',
  categoryId: cat,
  note: note,
  createdAt: DateTime(2026, 9, 20),
);

const _people = [
  Person(id: 'ahmed', name: 'Ahmed Khan'),
  Person(id: 'sara', name: 'Sara'),
  Person(id: 'bilal', name: 'Bilal'),
  Person(id: 'zain', name: 'Zain'),
];

AppData _data() => AppData(
  people: _people,
  txns: [
    _split('t1', 'ahmed', 500000),
    _split('t2', 'sara', 200000),
    _split('t3', 'bilal', 900000),
    _split('t4', 'zain', 300000, owedToYou: false),
  ],
);

List<SettleSuggestion> _suggest(
  AppData data,
  TxnType type,
  int? minor, [
  String text = '',
]) => SettleMatch.suggest(
  positions: PeopleLedger.openPositions(data),
  type: type,
  amountMinor: minor,
  text: text,
);

List<String> _names(List<SettleSuggestion> s) =>
    s.map((e) => e.position.name).toList();

void main() {
  group('SettleMatch.suggest', () {
    test('money in only offers people who owe you, biggest first', () {
      final s = _suggest(_data(), TxnType.income, 12345);
      expect(_names(s), ['Bilal', 'Ahmed Khan', 'Sara']);
      expect(s.every((e) => e.kind == DebtKind.owedToYou), isTrue);
    });

    test('money out only offers people you owe', () {
      final s = _suggest(_data(), TxnType.expense, 100);
      expect(_names(s), ['Zain']);
      expect(s.single.openMinor, 300000);
    });

    test('a transfer settles nobody', () {
      expect(_suggest(_data(), TxnType.transfer, 500000), isEmpty);
    });

    test('an exact amount outranks a name, which outranks size', () {
      final s = _suggest(
        _data(),
        TxnType.income,
        200000,
        'Rs 2,000.00 received from AHMED K via Raast',
      );
      expect(_names(s), ['Sara', 'Ahmed Khan', 'Bilal']);
      expect(s[0].exactAmount, isTrue);
      expect(s[1].namedInText, isTrue);
      expect(s[2].exactAmount || s[2].namedInText, isFalse);
    });

    test('names match whole words only, never an initial', () {
      final data = AppData(
        people: const [Person(id: 'al', name: 'Al Sara')],
        txns: [_split('t', 'al', 100)],
      );
      final p = PeopleLedger.openPositions(data).single;
      expect(SettleMatch.mentions('from Al Rashid', p), isFalse);
      expect(SettleMatch.mentions('from Saraswati', p), isFalse);
      expect(SettleMatch.mentions('from sara.', p), isTrue);
    });

    test('a person already square is not offered', () {
      final data = _data();
      final settled = AppData(
        people: data.people,
        txns: [
          ...data.txns,
          PeopleLedger.settlementTxn(
            id: 's',
            person: 'Sara',
            personId: 'sara',
            kind: DebtKind.owedToYou,
            amountMinor: 200000,
            accountId: 'bank',
            date: DateTime(2026, 9, 10),
            createdAt: DateTime(2026, 9, 10),
          ),
        ],
      );
      expect(
        _names(_suggest(settled, TxnType.income, 1)),
        isNot(contains('Sara')),
      );
    });
  });

  group('SettleMatch.apply', () {
    SettleSuggestion pick(AppData data, TxnType type, String name) =>
        _suggest(data, type, null).firstWhere((s) => s.position.name == name);

    AppData withTxns(AppData data, List<Txn> txns) =>
        AppData(people: data.people, txns: [...data.txns, ...txns]);

    test('an exact repayment clears the person off the open list', () {
      final data = _data();
      final out = SettleMatch.apply(
        base: _detected(TxnType.income, 500000, note: 'Raast in'),
        s: pick(data, TxnType.income, 'Ahmed Khan'),
        newId: () => fail('no remainder expected'),
      );
      expect(out, hasLength(1));
      final t = out.single;
      expect(t.id, 'new');
      expect(t.isSettlement, isTrue);
      expect(t.personId, 'ahmed');
      expect(t.ownShareMinor, 0);
      expect(t.note, 'Raast in');
      final after = withTxns(data, out);
      expect(PeopleLedger.forKey(after, 'ahmed')!.isClear, isTrue);
      expect(
        PeopleLedger.openPositions(after).map((p) => p.key),
        isNot(contains('ahmed')),
      );
    });

    test('a partial repayment leaves the remainder owed', () {
      final data = _data();
      final out = SettleMatch.apply(
        base: _detected(TxnType.income, 150000),
        s: pick(data, TxnType.income, 'Ahmed Khan'),
        newId: () => fail('no remainder expected'),
      );
      expect(out.single.amountMinor, 150000);
      expect(out.single.note, 'Settlement received');
      final after = withTxns(data, out);
      expect(PeopleLedger.forKey(after, 'ahmed')!.netMinor, 350000);
    });

    test('an overpayment settles the balance and keeps the rest as income', () {
      final data = _data();
      final out = SettleMatch.apply(
        base: _detected(TxnType.income, 600000),
        s: pick(data, TxnType.income, 'Ahmed Khan'),
        newId: () => 'extra',
      );
      expect(out, hasLength(2));
      expect(out[0].isSettlement, isTrue);
      expect(out[0].amountMinor, 500000);
      expect(out[1].id, 'extra');
      expect(out[1].isSettlement, isFalse);
      expect(out[1].type, TxnType.income);
      expect(out[1].amountMinor, 100000);
      // Cash through the account is unchanged: 5,000 + 1,000 = 6,000.
      expect(out.fold(0, (s, t) => s + t.amountMinor), 600000);
      expect(
        PeopleLedger.forKey(withTxns(data, out), 'ahmed')!.isClear,
        isTrue,
      );
    });

    test('paying back more than you owe keeps the category on the rest', () {
      final data = _data();
      final out = SettleMatch.apply(
        base: _detected(TxnType.expense, 350000, cat: 'food'),
        s: pick(data, TxnType.expense, 'Zain'),
        newId: () => 'extra',
      );
      expect(out[0].type, TxnType.expense);
      expect(out[0].isSettlement, isTrue);
      expect(out[0].amountMinor, 300000);
      expect(out[1].categoryId, 'food');
      expect(out[1].ownShareMinor, 50000);
      expect(PeopleLedger.forKey(withTxns(data, out), 'zain')!.isClear, isTrue);
    });

    test('relinking a saved income keeps its id and settles it', () {
      final data = _data();
      final saved = _detected(TxnType.income, 200000);
      final relinked = SettleMatch.relink(
        saved,
        pick(data, TxnType.income, 'Sara'),
      );
      expect(relinked.id, saved.id);
      expect(relinked.isSettlement, isTrue);
      expect(
        PeopleLedger.forKey(withTxns(data, [relinked]), 'sara')!.isClear,
        isTrue,
      );
    });
  });
}
