import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';

/// Label for the special "no category" filter value (`''`).
const String kUncategorizedLabel = 'Uncategorized';

/// The search box, the type / account / category pickers, and the summary of
/// what is currently narrowing the list.
class TxnFilterBar extends StatelessWidget {
  const TxnFilterBar({
    required this.data,
    required this.filters,
    required this.searchController,
    required this.onType,
    required this.onAccount,
    required this.onCategory,
    required this.onClearAll,
    super.key,
  });

  final AppData data;
  final TxnFilters filters;
  final TextEditingController searchController;
  final ValueChanged<TxnType?> onType;
  final ValueChanged<String?> onAccount;

  /// `null` clears the category filter; `''` selects uncategorized.
  final ValueChanged<String?> onCategory;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search notes, people, accounts',
              border: const OutlineInputBorder(),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => searchController.clear(),
                    ),
            ),
          ),
        ),
        _Pickers(
          data: data,
          filters: filters,
          onType: onType,
          onAccount: onAccount,
          onCategory: onCategory,
        ),
        if (filters.isActive)
          ActiveFilterSummary(
            data: data,
            filters: filters,
            onClearCategory: () => onCategory(null),
            onClearAll: onClearAll,
          ),
      ],
    );
  }
}

class _Pickers extends StatelessWidget {
  const _Pickers({
    required this.data,
    required this.filters,
    required this.onType,
    required this.onAccount,
    required this.onCategory,
  });

  final AppData data;
  final TxnFilters filters;
  final ValueChanged<TxnType?> onType;
  final ValueChanged<String?> onAccount;
  final ValueChanged<String?> onCategory;

  @override
  Widget build(BuildContext context) {
    // A category that no longer exists must not be handed to the dropdown —
    // it asserts on a value with no matching item.
    final id = filters.categoryId;
    final categoryValue =
        id == null || id.isEmpty || data.categoryById(id) != null ? id : null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          for (final (label, t) in [
            ('All', null),
            ('Expenses', TxnType.expense),
            ('Income', TxnType.income),
            ('Transfers', TxnType.transfer),
          ]) ...[
            ChoiceChip(
              label: Text(label),
              selected: filters.type == t,
              onSelected: (_) => onType(t),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          const SizedBox(width: AppSpacing.sm),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: filters.accountId,
              hint: const Text('All accounts'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All accounts'),
                ),
                for (final a in data.accounts)
                  DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
              ],
              onChanged: onAccount,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: categoryValue,
              hint: const Text('All categories'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All categories'),
                ),
                // Transactions with no category are filterable too — they are
                // the `''` bucket the dashboard breakdown also shows.
                const DropdownMenuItem<String?>(
                  value: '',
                  child: Text(kUncategorizedLabel),
                ),
                for (final c in data.categories)
                  DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: onCategory,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spells out what is hiding transactions right now, so a short list is never
/// a mystery, and gives one tap to undo it.
class ActiveFilterSummary extends StatelessWidget {
  const ActiveFilterSummary({
    required this.data,
    required this.filters,
    required this.onClearCategory,
    required this.onClearAll,
    super.key,
  });

  final AppData data;
  final TxnFilters filters;
  final VoidCallback onClearCategory;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          if (filters.categoryId != null)
            Flexible(
              child: InputChip(
                avatar: const Icon(Icons.label_outline, size: 18),
                label: Text(
                  'Category: ${categoryFilterLabel(data, filters.categoryId!)}',
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: onClearCategory,
                deleteIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip: 'Show all categories',
              ),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: onClearAll,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}

/// Human name for a category filter value (`''` = uncategorized).
String categoryFilterLabel(AppData data, String categoryId) =>
    categoryId.isEmpty
    ? kUncategorizedLabel
    : (data.categoryById(categoryId)?.name ?? kUncategorizedLabel);
