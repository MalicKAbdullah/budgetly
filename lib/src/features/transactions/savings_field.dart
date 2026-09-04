import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';

/// The three things a transaction can say about savings.
enum SavingsChoice {
  inherit('Inherit from category'),
  moveToSavings('Move to savings'),
  takeFromSavings('Take from savings');

  const SavingsChoice(this.label);
  final String label;

  /// The state an already-recorded earmark opens in. An explicit `0` has no
  /// direction, so it opens as "Move to savings" with a zero amount — which
  /// is exactly what it means: ignore the category, move nothing.
  static SavingsChoice forEarmark(int? minor) => switch (minor) {
    null => SavingsChoice.inherit,
    < 0 => SavingsChoice.takeFromSavings,
    _ => SavingsChoice.moveToSavings,
  };
}

/// Savings for one transaction: inherit the category's rule, or override it
/// with an amount in either direction. Works the same on a transaction
/// recorded long before savings existed.
class SavingsField extends StatelessWidget {
  const SavingsField({
    required this.choice,
    required this.amount,
    required this.categoryEffect,
    required this.flowMinor,
    required this.code,
    required this.onChoice,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final SavingsChoice choice;
  final TextEditingController amount;

  /// The rule on the category currently picked, which "Inherit" resolves to.
  final SavingsEffect categoryEffect;

  /// What this transaction costs or earns — the most that can be earmarked.
  final int flowMinor;

  final String code;
  final ValueChanged<SavingsChoice> onChoice;
  final VoidCallback onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A dropdown rather than a segmented button: the three labels have to
        // stay spelled out to be unambiguous, and three of them do not fit a
        // phone-width segmented row without truncating.
        DropdownButtonFormField<SavingsChoice>(
          isExpanded: true,
          initialValue: choice,
          decoration: const InputDecoration(labelText: 'Savings'),
          items: [
            for (final c in SavingsChoice.values)
              DropdownMenuItem(value: c, child: Text(c.label)),
          ],
          onChanged: (v) => onChoice(v ?? choice),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (choice == SavingsChoice.inherit)
          Text(
            _inheritPreview(),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: choice == SavingsChoice.moveToSavings
                  ? 'Amount to reserve as savings'
                  : 'Amount to release from savings',
              prefixText: '$code ',
              helperText: 'Reserving money is not spending it. '
                  'Enter 0 to ignore the category rule.',
              helperMaxLines: 2,
              errorText: errorText,
            ),
            onChanged: (_) => onChanged(),
          ),
      ],
    );
  }

  /// Never leave "Inherit" a mystery: say what it resolves to right now.
  String _inheritPreview() => switch (categoryEffect) {
    SavingsEffect.none =>
      'This category has no savings rule, so this is not a savings movement.',
    SavingsEffect.addsToSavings =>
      'This category adds to savings: '
          '${Money.format(flowMinor, code: code)} is reserved.',
    SavingsEffect.takesFromSavings =>
      'This category takes from savings: '
          '${Money.format(flowMinor, code: code)} is released.',
  };
}

/// The savings part of the transaction editor's draft — the chosen state, the
/// typed amount and the last validation problem, mirroring [SplitDraft].
final class SavingsDraft {
  SavingsChoice choice = SavingsChoice.inherit;
  final TextEditingController amount = TextEditingController();
  String? error;

  /// Opens on whatever [txn] already carries. A transaction recorded before
  /// savings existed carries nothing, so it opens on the category rule.
  void load(Txn txn) {
    choice = SavingsChoice.forEarmark(txn.savingsEffectMinor);
    final minor = txn.savingsEffectMinor;
    if (minor != null) amount.text = Money.toInput(minor.abs());
  }

  void dispose() => amount.dispose();

  /// The problem to show, or null when the draft can be saved. [flowMinor] is
  /// what the transaction costs or earns: money that never moved cannot be
  /// reserved, so it is the ceiling on the earmark.
  String? validate({required bool canEarmark, required int flowMinor}) {
    if (!canEarmark || choice == SavingsChoice.inherit) return null;
    final entered = Money.parse(amount.text);
    if (entered == null) return 'Enter the savings amount.';
    if (entered > flowMinor) {
      return 'That is more than this transaction is worth.';
    }
    return null;
  }

  /// The signed override to store — only meaningful once [validate] passed.
  int? earmarkFor({required bool canEarmark}) {
    if (!canEarmark || choice == SavingsChoice.inherit) return null;
    final entered = Money.parse(amount.text)!;
    return choice == SavingsChoice.moveToSavings ? entered : -entered;
  }
}
