import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/money.dart';

/// One person on the split being edited: who, and how much of the split total
/// is theirs. The controller lives in the editor so the text survives rebuilds.
final class SplitRow {
  SplitRow({required this.personId, required this.amount});

  final String personId;
  final TextEditingController amount;

  int get amountMinor => Money.parse(amount.text) ?? 0;
}

/// The split being edited, and the rules it has to satisfy before it can be
/// saved.
///
/// [share] is the authoritative total — the receivable or the payable the money
/// math already uses. The rows only divide it up, and [validate] refuses a
/// division that does not add up, so a saved transaction always satisfies
/// [Txn.splitsBalanced].
final class SplitDraft {
  final TextEditingController share = TextEditingController();
  final List<SplitRow> rows = <SplitRow>[];

  /// A split points one way only — either they owe the owner or the owner owes
  /// them. The editor offers the two as a choice, so both can never be set.
  DebtKind kind = DebtKind.owedToYou;

  /// Reads an existing transaction, including one written before this version:
  /// its scalar total, and its people when it has them.
  void load(Txn txn) {
    kind = txn.payableMinor > 0 ? DebtKind.youOwe : DebtKind.owedToYou;
    share.text = Money.toInput(txn.splitTotalMinor);
    rows.clear();
    for (final s in txn.splits) {
      rows.add(
        SplitRow(
          personId: s.personId,
          amount: TextEditingController(text: Money.toInput(s.amountMinor)),
        ),
      );
    }
  }

  void dispose() {
    share.dispose();
    for (final r in rows) {
      r.amount.dispose();
    }
  }

  int get shareMinor => Money.parse(share.text) ?? 0;
  int get assignedMinor => rows.fold(0, (s, r) => s + r.amountMinor);
  int get unassignedMinor => shareMinor - assignedMinor;

  bool contains(String personId) => rows.any((r) => r.personId == personId);
  Set<String> get personIds => {for (final r in rows) r.personId};

  void add(String personId) {
    if (contains(personId)) return;
    rows.add(
      SplitRow(
        personId: personId,
        amount: TextEditingController(text: ''),
      ),
    );
  }

  void removeAt(int index) {
    rows.removeAt(index).amount.dispose();
  }

  /// Divides the split total equally; the rounding remainder goes to the first
  /// rows, a minor unit each, so the parts always add back up to the total.
  void splitEvenly() {
    if (rows.isEmpty) return;
    final total = shareMinor;
    final base = total ~/ rows.length;
    var extra = total - base * rows.length;
    for (final r in rows) {
      final amount = base + (extra > 0 ? 1 : 0);
      if (extra > 0) extra--;
      r.amount.text = Money.toInput(amount);
    }
  }

  /// The reason this split cannot be saved, or null when it can.
  /// [paidMinor] is what the owner paid out of their own account.
  String? validate({required int paidMinor}) {
    final total = shareMinor;
    if (total <= 0) return 'Enter how much the split is for.';
    if (kind == DebtKind.owedToYou && total > paidMinor) {
      return 'The part owed back cannot exceed what you paid.';
    }
    if (rows.isEmpty) return null;
    if (rows.any((r) => r.amountMinor <= 0)) {
      return 'Give everyone on the split an amount, or remove them.';
    }
    if (unassignedMinor != 0) {
      return unassignedMinor > 0
          ? 'Assign the rest of the split total, or use Split evenly.'
          : 'The amounts add up to more than the split total.';
    }
    return null;
  }

  int get reimbursableMinor => kind == DebtKind.owedToYou ? shareMinor : 0;
  int get payableMinor => kind == DebtKind.youOwe ? shareMinor : 0;

  List<TxnSplit> toSplits() => [
    for (final r in rows)
      TxnSplit(personId: r.personId, amountMinor: r.amountMinor),
  ];
}

/// The split section of the transaction editor: which way the split points, the
/// split total, and who owes which part of it — with a running "your share" so
/// the owner always sees the number that will count as their spending, and a
/// running "unassigned" so a half-shared bill can never be saved.
class SplitFields extends StatelessWidget {
  const SplitFields({
    required this.draft,
    required this.nameFor,
    required this.paidMinor,
    required this.code,
    required this.onAddPerson,
    required this.onChanged,
    super.key,
  });

  final SplitDraft draft;

  /// Display name for a person id.
  final String Function(String personId) nameFor;

  /// What the owner paid out of their own account (the Amount field).
  final int paidMinor;
  final String code;

  /// Opens the person picker; the editor adds the result to [draft].
  final VoidCallback onAddPerson;

  /// Called after any edit, so the editor can rebuild the running totals.
  final VoidCallback onChanged;

  int get _shareMinor => draft.shareMinor;
  int get _unassignedMinor => draft.unassignedMinor;
  List<SplitRow> get rows => draft.rows;

  bool get _receivable => draft.kind == DebtKind.owedToYou;

  /// Their share of what the owner paid, or the owner's share someone else
  /// fronted — the same arithmetic the model uses.
  String get _yourShare {
    final owed = _receivable ? _shareMinor : 0;
    final owe = _receivable ? 0 : _shareMinor;
    final share = (paidMinor - owed + owe).clamp(0, 1 << 62);
    return Money.format(share, code: code);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<DebtKind>(
          segments: const [
            ButtonSegment(
              value: DebtKind.owedToYou,
              label: Text('They owe me'),
            ),
            ButtonSegment(value: DebtKind.youOwe, label: Text('I owe them')),
          ],
          selected: {draft.kind},
          onSelectionChanged: (s) {
            draft.kind = s.first;
            onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: draft.share,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: _receivable
                ? 'Amount owed back to you'
                : 'Amount you owe',
            prefixText: '$code ',
            helperMaxLines: 2,
            helperText: _receivable
                ? 'The part of what you paid that comes back to you'
                : 'Your share that they fronted — no cash left your account',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your share: $_yourShare — this is what counts as your spending.',
          style: text.bodySmall?.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Who owes it', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < rows.length; i++)
          _PersonAmountRow(
            name: nameFor(rows[i].personId),
            controller: rows[i].amount,
            code: code,
            onRemove: () {
              draft.removeAt(i);
              onChanged();
            },
            onChanged: onChanged,
          ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: onAddPerson,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add person'),
            ),
            if (rows.isNotEmpty && _shareMinor > 0)
              OutlinedButton.icon(
                onPressed: () {
                  draft.splitEvenly();
                  onChanged();
                },
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Split evenly'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _Remaining(
          unassignedMinor: _unassignedMinor,
          anyPeople: rows.isNotEmpty,
          blankRows: rows.where((r) => r.amountMinor <= 0).length,
          code: code,
        ),
      ],
    );
  }
}

class _PersonAmountRow extends StatelessWidget {
  const _PersonAmountRow({
    required this.name,
    required this.controller,
    required this.code,
    required this.onRemove,
    required this.onChanged,
  });

  final String name;
  final TextEditingController controller;
  final String code;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: name,
                prefixText: '$code ',
                prefixIcon: const Icon(Icons.person_outline),
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remove $name',
          ),
        ],
      ),
    );
  }
}

/// The live "still to assign" line — the one number that says whether the
/// split adds up.
class _Remaining extends StatelessWidget {
  const _Remaining({
    required this.unassignedMinor,
    required this.anyPeople,
    required this.blankRows,
    required this.code,
  });

  final int unassignedMinor;
  final bool anyPeople;

  /// People on the split who have no amount yet.
  final int blankRows;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.bodySmall;
    if (!anyPeople) {
      return Text(
        'Nobody named yet — the whole split stays under '
        '"${PeopleLedger.unnamedLabel}". Add people to track who owes what.',
        style: text?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    if (blankRows > 0) {
      return Text(
        'Give everyone on the split an amount.',
        style: text?.copyWith(color: scheme.error),
      );
    }
    final amount = Money.format(unassignedMinor.abs(), code: code);
    final (line, color) = switch (unassignedMinor) {
      0 => ('Fully assigned.', scheme.onSurfaceVariant),
      > 0 => ('$amount still to assign.', scheme.error),
      _ => ('$amount over the split total.', scheme.error),
    };
    return Text(line, style: text?.copyWith(color: color));
  }
}
