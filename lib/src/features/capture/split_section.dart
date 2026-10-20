import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/features/capture/split_draft.dart';

/// The split editor of the capture review sheet: who owes which part of the
/// payment, how the owner's own share is filed across categories, and a live
/// line saying what is still unplaced.
class CaptureSplitSection extends StatelessWidget {
  const CaptureSplitSection({
    required this.draft,
    required this.totalMinor,
    required this.categories,
    required this.nameFor,
    required this.code,
    required this.onAddPerson,
    required this.onChanged,
    super.key,
  });

  final CaptureSplitDraft draft;

  /// The payment being divided — the review sheet's Amount field.
  final int totalMinor;
  final List<Category> categories;
  final String Function(String personId) nameFor;
  final String code;

  /// Opens the person picker; the sheet adds the result to [draft].
  final VoidCallback onAddPerson;

  /// Called after any edit so the sheet rebuilds the running totals.
  final VoidCallback onChanged;

  void _edit(VoidCallback change) {
    change();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amounts = draft.peopleMinor(totalMinor);
    final remaining = draft.plan(totalMinor).remainingMinor;
    final problem = draft.validate(totalMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Shared with', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        if (draft.people.isNotEmpty) ...[
          SegmentedButton<PeopleInput>(
            segments: const [
              ButtonSegment(value: PeopleInput.amount, label: Text('Amount')),
              ButtonSegment(value: PeopleInput.percent, label: Text('Percent')),
            ],
            selected: {draft.input},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                _edit(() => draft.setInput(s.first, totalMinor)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (var i = 0; i < draft.people.length; i++)
          SplitPersonRow(
            key: ObjectKey(draft.people[i]),
            name: nameFor(draft.people[i].personId),
            controller: draft.people[i].amount,
            percent: draft.input == PeopleInput.percent,
            resolvedMinor: amounts[i],
            code: code,
            onRemove: () => _edit(() => draft.removePerson(i)),
            onChanged: onChanged,
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: onAddPerson,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add person'),
            ),
            if (draft.people.isNotEmpty && totalMinor > 0) ...[
              OutlinedButton.icon(
                onPressed: () => _edit(
                  () => draft.splitEqually(totalMinor, includeMe: true),
                ),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Equally, with me'),
              ),
              OutlinedButton.icon(
                onPressed: () => _edit(
                  () => draft.splitEqually(totalMinor, includeMe: false),
                ),
                icon: const Icon(Icons.groups_outlined, size: 18),
                label: const Text('Equally, just them'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('My share', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < draft.categories.length; i++)
          SplitCategoryRow(
            // Keyed by row so a dropdown never keeps a removed row's choice.
            key: ObjectKey(draft.categories[i]),
            row: draft.categories[i],
            categories: categories,
            code: code,
            onFillRest: () => _edit(() => draft.fillRest(i, totalMinor)),
            onRemove: () => _edit(() => draft.removeCategory(i)),
            onChanged: onChanged,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _edit(draft.addCategory),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add category'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SplitRemainderLine(
          owedBackMinor: amounts.fold(0, (s, a) => s + a),
          remainingMinor: remaining,
          code: code,
        ),
        // An unplaced amount is already said above; anything else that blocks
        // saving is said here.
        if (remaining == 0 && problem != null)
          Text(
            problem,
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

/// One person's part, typed as an amount or a percentage of the payment. In
/// percent mode the resolved amount shows underneath.
class SplitPersonRow extends StatelessWidget {
  const SplitPersonRow({
    required this.name,
    required this.controller,
    required this.percent,
    required this.resolvedMinor,
    required this.code,
    required this.onRemove,
    required this.onChanged,
    super.key,
  });

  final String name;
  final TextEditingController controller;
  final bool percent;
  final int resolvedMinor;
  final String code;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: name,
              prefixIcon: const Icon(Icons.person_outline),
              prefixText: percent ? null : Money.symbol(code),
              suffixText: percent ? '%' : null,
              helperText: percent
                  ? Money.format(resolvedMinor, code: code)
                  : null,
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

/// One category the owner's share is filed under, with its amount.
class SplitCategoryRow extends StatelessWidget {
  const SplitCategoryRow({
    required this.row,
    required this.categories,
    required this.code,
    required this.onFillRest,
    required this.onRemove,
    required this.onChanged,
    super.key,
  });

  final CategoryRow row;
  final List<Category> categories;
  final String code;
  final VoidCallback onFillRest;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: row.categoryId,
            decoration: const InputDecoration(
              labelText: 'Category',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Uncategorized')),
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) {
              row.categoryId = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 120,
          child: TextField(
            controller: row.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: Money.symbol(code),
              isDense: true,
            ),
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          onPressed: onFillRest,
          icon: const Icon(Icons.vertical_align_bottom),
          tooltip: 'Put the rest here',
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: 'Remove category',
        ),
      ],
    ),
  );
}

/// The live totals: what others owe back, and what is still unplaced — the one
/// number that says whether the split adds up.
class SplitRemainderLine extends StatelessWidget {
  const SplitRemainderLine({
    required this.owedBackMinor,
    required this.remainingMinor,
    required this.code,
    super.key,
  });

  final int owedBackMinor;
  final int remainingMinor;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final left = Money.format(remainingMinor.abs(), code: code);
    final (line, color) = switch (remainingMinor) {
      0 => ('Fully assigned.', scheme.onSurfaceVariant),
      > 0 => ('$left left to assign.', scheme.error),
      _ => ('$left over the total.', scheme.error),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Owed back to you: ${Money.format(owedBackMinor, code: code)}',
          style: style?.copyWith(color: scheme.onSurface),
        ),
        Text(line, style: style?.copyWith(color: color)),
      ],
    );
  }
}
