import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
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
    final c = SuiteColors.of(context);
    final amounts = draft.peopleMinor(totalMinor);
    final remaining = draft.plan(totalMinor).remainingMinor;
    final problem = draft.validate(totalMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeading('Shared with', color: c.textSecondary),
        if (draft.people.isNotEmpty) ...[
          AppSegmentedControl<PeopleInput>(
            segments: const [
              AppSegment(value: PeopleInput.amount, label: 'Amount'),
              AppSegment(value: PeopleInput.percent, label: 'Percent'),
            ],
            selected: draft.input,
            onChanged: (v) => _edit(() => draft.setInput(v, totalMinor)),
          ),
          const SizedBox(height: AppSpacing.smd),
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
          runSpacing: AppSpacing.sm,
          children: [
            VaultButton(
              label: 'Add person',
              icon: Icons.person_add_alt_rounded,
              variant: VaultButtonVariant.secondary,
              compact: true,
              isFullWidth: false,
              onPressed: onAddPerson,
            ),
            if (draft.people.isNotEmpty && totalMinor > 0) ...[
              VaultButton(
                label: 'Equally, with me',
                icon: Icons.call_split_rounded,
                variant: VaultButtonVariant.secondary,
                compact: true,
                isFullWidth: false,
                onPressed: () => _edit(
                  () => draft.splitEqually(totalMinor, includeMe: true),
                ),
              ),
              VaultButton(
                label: 'Equally, just them',
                icon: Icons.groups_outlined,
                variant: VaultButtonVariant.secondary,
                compact: true,
                isFullWidth: false,
                onPressed: () => _edit(
                  () => draft.splitEqually(totalMinor, includeMe: false),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _SubHeading('My share', color: c.textSecondary),
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
          child: VaultButton(
            label: 'Add category',
            icon: Icons.add_rounded,
            variant: VaultButtonVariant.secondary,
            compact: true,
            isFullWidth: false,
            onPressed: () => _edit(draft.addCategory),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SplitRemainderLine(
          owedBackMinor: amounts.fold(0, (s, a) => s + a),
          remainingMinor: remaining,
          code: code,
        ),
        // An unplaced amount is already said above; anything else that blocks
        // saving is said here.
        if (remaining == 0 && problem != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            problem,
            style: AppTextStyles.bodySmall.copyWith(color: c.negative),
          ),
        ],
      ],
    );
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text.toUpperCase(),
      style: AppTextStyles.overline.copyWith(color: color),
    ),
  );
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
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
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
          icon: const Icon(Icons.close_rounded),
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
    padding: const EdgeInsets.only(bottom: AppSpacing.smd),
    // Two lines: the sheet is too narrow for a readable category name, an
    // amount and two actions side by side.
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: row.categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Uncategorized'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  row.categoryId = v;
                  onChanged();
                },
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Remove category',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: row.amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: Money.symbol(code),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            IconButton(
              onPressed: onFillRest,
              icon: const Icon(Icons.vertical_align_bottom_rounded),
              tooltip: 'Put the rest here',
            ),
          ],
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
    final c = SuiteColors.of(context);
    final left = Money.format(remainingMinor.abs(), code: code);
    final done = remainingMinor == 0;
    final line = switch (remainingMinor) {
      0 => 'Fully assigned.',
      > 0 => '$left left to assign.',
      _ => '$left over the total.',
    };
    final tone = done ? c.positive : c.negative;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.smd),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_outline_rounded : Icons.error_outline,
            size: 20,
            color: tone,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Owed back to you: ${Money.format(owedBackMinor, code: code)}',
                  style: AppTextStyles.labelStrong.copyWith(
                    color: c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: done ? c.textSecondary : c.negative,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
