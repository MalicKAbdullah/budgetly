import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/features/capture/transfer_hint.dart';

/// Expense / Income / Transfer. A captured alert can be any of the three — a
/// cash withdrawal moves money between the owner's own accounts.
class CaptureModeSelector extends StatelessWidget {
  const CaptureModeSelector({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<CaptureMode>(
    segments: [
      for (final m in CaptureMode.values)
        ButtonSegment(value: m, label: Text(m.label)),
    ],
    selected: {mode},
    showSelectedIcon: false,
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// One account dropdown. Used on its own for expense/income and twice, as
/// From and To, for a transfer.
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    isExpanded: true,
    initialValue: accounts.any((a) => a.id == value) ? value : null,
    decoration: InputDecoration(
      labelText: label,
      errorText: errorText,
      border: const OutlineInputBorder(),
    ),
    items: [
      // Just the name: an account called "Cash" of type Cash would otherwise
      // read "Cash · Cash".
      for (final a in accounts)
        DropdownMenuItem(value: a.id, child: Text(a.name)),
    ],
    onChanged: onChanged,
  );
}

/// Category, with an explicit "Uncategorized" choice. Hidden for transfers —
/// moving your own money between accounts is not spending on anything.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    required this.categories,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<Category> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    isExpanded: true,
    initialValue: value,
    decoration: const InputDecoration(
      labelText: 'Category',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem(value: null, child: Text('Uncategorized')),
      for (final c in categories)
        DropdownMenuItem(value: c.id, child: Text(c.name)),
    ],
    onChanged: onChanged,
  );
}

/// The alert exactly as it arrived, so the owner can check what was read.
class CapturedRawText extends StatelessWidget {
  const CapturedRawText({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      // onSurface, not the container's own "on" colour: an earlier card lost
      // its text into its background in one of the two themes.
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}
