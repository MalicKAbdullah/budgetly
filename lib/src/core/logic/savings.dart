import 'package:flutter/foundation.dart' show immutable;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/logic/flow.dart';
import 'package:budgetly/src/core/logic/people.dart';

/// Where the owner stands against their savings target at one moment.
@immutable
final class SavingsPosition {
  const SavingsPosition({
    required this.heldMinor,
    required this.countedReceivablesMinor,
    required this.uncountedReceivablesMinor,
    required this.targetMinor,
  });

  /// Real cash across every active account — [Balances.netWorthMinor].
  final int heldMinor;

  /// Outstanding money lent out that the owner marked as still theirs.
  final int countedReceivablesMinor;

  /// Outstanding money lent out that is treated as gone. Shown, never added.
  final int uncountedReceivablesMinor;

  final int targetMinor;

  /// Everything that counts toward the target.
  int get positionMinor => heldMinor + countedReceivablesMinor;

  /// What is free to spend without breaking the target. Negative is real and
  /// meaningful: the owner is that far into their savings.
  int get freeToSpendMinor => positionMinor - targetMinor;

  bool get isDipping => freeToSpendMinor < 0;

  bool get hasTarget => targetMinor > 0;

  /// How far along the target is, clamped for display only.
  double get progress {
    if (targetMinor <= 0) return 0;
    final ratio = positionMinor / targetMinor;
    return ratio.isNaN ? 0 : ratio.clamp(0.0, 1.0);
  }
}

/// How the position moved across the selected window, carry-over included.
@immutable
final class SavingsPeriod {
  const SavingsPeriod({
    required this.carriedInMinor,
    required this.closingMinor,
  });

  /// The position as it stood the day before the window opened. Money saved in
  /// earlier months lives here, which is why it can never fall off a monthly
  /// view.
  final int carriedInMinor;

  /// The position at the end of the window.
  final int closingMinor;

  int get changeMinor => closingMinor - carriedInMinor;
}

/// Savings as a **line the owner draws**, not a pot they fill.
///
/// The owner sets one number — the target, the amount they want to always
/// have. Everything they hold across every account counts toward it
/// automatically; no transaction is ever tagged. What they read off the screen
/// is `free to spend = position - target`.
///
/// **Money lent out** is the single judgement call. Lending a friend cash has
/// genuinely removed it, so by default a receivable is not counted. When the
/// owner is only passing money through on somebody else's behalf, they mark
/// that loan and its outstanding amount counts again.
///
/// **One resolver.** [position] is the only place "what counts" is decided,
/// and every screen and derived number goes through it. Because the flag is
/// read at the moment a number is computed, toggling one loan re-derives every
/// historical position — nothing is stored and nothing goes stale.
///
/// **Neutrality falls out of the arithmetic.** A transfer moves money between
/// two accounts that are both inside [Balances.netWorthMinor], so it cannot
/// change the position. A settlement on a counted loan raises cash and lowers
/// the outstanding amount by the same figure, so it cannot either. Neither is
/// ever income or spending — no special case is needed to keep it that way.
abstract final class Savings {
  /// Where the owner stands, over every transaction or only those on or before
  /// [asOf].
  ///
  /// The dated view rebuilds the snapshot and reuses the very same
  /// [Balances.netWorthMinor] and [PeopleLedger.positions], so a historical
  /// figure can never drift from how today's is computed.
  static SavingsPosition position(AppData data, {DateTime? asOf}) {
    final scoped = asOf == null ? data : _upTo(data, asOf);
    var counted = 0;
    var uncounted = 0;
    for (final person in PeopleLedger.positions(scoped)) {
      for (final entry in person.openEntries(DebtKind.owedToYou)) {
        if (entry.txn.receivableCountsAsSavings) {
          counted += entry.outstandingMinor;
        } else {
          uncounted += entry.outstandingMinor;
        }
      }
    }
    return SavingsPosition(
      heldMinor: Balances.netWorthMinor(scoped),
      countedReceivablesMinor: counted,
      uncountedReceivablesMinor: uncounted,
      targetMinor: data.savingsTargetMinor,
    );
  }

  /// The window's carry-over and closing position.
  static SavingsPeriod period(AppData data, DateTime start, DateTime end) =>
      SavingsPeriod(
        carriedInMinor: position(
          data,
          asOf: DateTime(start.year, start.month, start.day - 1),
        ).positionMinor,
        closingMinor: position(data, asOf: end).positionMinor,
      );

  /// Every open loan the owner has out, newest first, for the screen that lets
  /// them decide which ones still count as their money.
  static List<DebtEntry> openLoans(AppData data) {
    final rows = <DebtEntry>[
      for (final person in PeopleLedger.positions(data))
        ...person.openEntries(DebtKind.owedToYou),
    ];
    rows.sort((a, b) => b.txn.date.compareTo(a.txn.date));
    return rows;
  }

  /// Opening balances are timeless, so only the transactions are filtered.
  static AppData _upTo(AppData data, DateTime day) => data.copyWith(
    txns: [
      for (final t in data.txns)
        if (!t.date.isAfter(DashboardFlow.endOfDay(day))) t,
    ],
  );
}
