import 'package:flutter/widgets.dart';
import 'package:budgetly/src/core/logic/capture_split.dart';
import 'package:budgetly/src/core/logic/split_allocation.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/transactions/split_fields.dart';

/// How the people's parts are typed in. Either way they end up as minor-unit
/// [TxnSplit]s; percent is only an input convenience.
enum PeopleInput { amount, percent }

/// One category the owner's own share is filed under.
final class CategoryRow {
  CategoryRow({required this.categoryId, required int amountMinor})
    : amount = TextEditingController(text: Money.toInput(amountMinor));

  String? categoryId;
  final TextEditingController amount;

  int get amountMinor => Money.parse(amount.text) ?? 0;
}

/// The split of a detected expense being edited in the review sheet. Holds the
/// text controllers so typed values survive rebuilds; [plan] turns them into
/// the [CaptureSplit] that is validated and saved.
///
/// The people rows reuse the transaction editor's [SplitRow]. In
/// [PeopleInput.percent] their text is a percentage of the whole payment.
final class CaptureSplitDraft {
  final List<SplitRow> people = <SplitRow>[];
  final List<CategoryRow> categories = <CategoryRow>[];
  PeopleInput input = PeopleInput.amount;

  /// Opens the split with the whole payment filed under the category already
  /// chosen, so turning it on changes nothing until something is divided.
  void start({required int totalMinor, required String? categoryId}) {
    if (categories.isNotEmpty || people.isNotEmpty) return;
    categories.add(
      CategoryRow(categoryId: categoryId, amountMinor: totalMinor),
    );
  }

  void dispose() {
    for (final r in people) {
      r.amount.dispose();
    }
    for (final r in categories) {
      r.amount.dispose();
    }
  }

  Set<String> get personIds => {for (final r in people) r.personId};

  void addPerson(String personId) {
    if (personIds.contains(personId)) return;
    people.add(SplitRow(personId: personId, amount: TextEditingController()));
  }

  void removePerson(int index) => people.removeAt(index).amount.dispose();

  void addCategory() =>
      categories.add(CategoryRow(categoryId: null, amountMinor: 0));

  void removeCategory(int index) => categories.removeAt(index).amount.dispose();

  /// What each person row holds as minor units: an amount, or in percent mode
  /// a percentage in basis points (`33.33` → 3333).
  List<int> get _typedMinor => [for (final r in people) r.amountMinor];

  /// Percentages that cannot be turned into amounts, or null.
  String? get _percentProblem {
    if (input != PeopleInput.percent) return null;
    final sum = _typedMinor.fold<int>(0, (s, b) => s + b);
    return sum > SplitAllocation.whole ? 'The percentages exceed 100%.' : null;
  }

  /// Each person's part of [totalMinor] in minor units. Percentages are
  /// allocated together with the owner's implied rest, so the parts round to
  /// whole minor units without drifting off the total.
  List<int> peopleMinor(int totalMinor) {
    final typed = _typedMinor;
    if (input == PeopleInput.amount) return typed;
    final rest = SplitAllocation.whole - typed.fold<int>(0, (s, b) => s + b);
    // Over 100% there is no owner's rest to round against; each part is then
    // its plain share, and the overshoot shows as over the total.
    if (rest < 0) {
      return [for (final b in typed) totalMinor * b ~/ SplitAllocation.whole];
    }
    return SplitAllocation.byBasisPoints(totalMinor, [...typed, rest])
      ..removeLast();
  }

  CaptureSplit plan(int totalMinor) {
    final amounts = peopleMinor(totalMinor);
    return CaptureSplit(
      totalMinor: totalMinor,
      people: [
        for (var i = 0; i < people.length; i++)
          TxnSplit(personId: people[i].personId, amountMinor: amounts[i]),
      ],
      parts: [
        for (final c in categories)
          CategoryPart(categoryId: c.categoryId, amountMinor: c.amountMinor),
      ],
    );
  }

  /// The reason the split cannot be saved, or null when it can.
  String? validate(int totalMinor) =>
      _percentProblem ?? plan(totalMinor).validate();

  /// Switches how people's parts are typed, converting what is there so the
  /// split itself does not change.
  void setInput(PeopleInput next, int totalMinor) {
    if (next == input) return;
    final amounts = peopleMinor(totalMinor);
    input = next;
    for (var i = 0; i < people.length; i++) {
      final value = next == PeopleInput.amount || totalMinor == 0
          ? amounts[i]
          : (amounts[i] * SplitAllocation.whole / totalMinor).round();
      people[i].amount.text = Money.toInput(value);
    }
  }

  /// Equal shares for everyone on the split. With [includeMe] the owner is one
  /// of the shares and keeps any rounding remainder; their share is filed
  /// under the first category. Without it the people owe the whole payment and
  /// nothing is filed as the owner's spending.
  void splitEqually(int totalMinor, {required bool includeMe}) {
    if (people.isEmpty) return;
    input = PeopleInput.amount;
    final shares = SplitAllocation.equal(
      totalMinor,
      people.length + (includeMe ? 1 : 0),
    );
    final theirs = includeMe ? shares.skip(1).toList() : shares;
    for (var i = 0; i < people.length; i++) {
      people[i].amount.text = Money.toInput(theirs[i]);
    }
    final keep = categories.isEmpty ? null : categories.first.categoryId;
    while (categories.isNotEmpty) {
      removeCategory(0);
    }
    if (includeMe) {
      categories.add(CategoryRow(categoryId: keep, amountMinor: shares.first));
    }
  }

  /// Adds whatever is still unplaced to the category at [index].
  void fillRest(int index, int totalMinor) {
    final row = categories[index];
    final next = row.amountMinor + plan(totalMinor).remainingMinor;
    row.amount.text = Money.toInput(next < 0 ? 0 : next);
  }
}
