import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: AppSearchField(
            controller: searchController,
            hint: 'Search notes, people, accounts',
          ),
        ),
        const SizedBox(height: AppSpacing.smd),
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
    final accountName = data.accountById(filters.accountId)?.name;
    // A category that no longer exists reads as no filter at all.
    final id = filters.categoryId;
    final categoryName = id == null
        ? null
        : id.isEmpty
        ? kUncategorizedLabel
        : data.categoryById(id)?.name;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Row(
        children: [
          for (final (label, t) in [
            ('All', null),
            ('Expenses', TxnType.expense),
            ('Income', TxnType.income),
            ('Transfers', TxnType.transfer),
          ]) ...[
            AppChip(
              label: label,
              selected: filters.type == t,
              onTap: () => onType(t),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            color: SuiteColors.of(context).border,
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: accountName ?? 'All accounts',
            icon: Icons.account_balance_outlined,
            selected: accountName != null,
            onTap: () async {
              final picked = await _pick(context, 'Account', [
                (null, 'All accounts'),
                for (final a in data.accounts) (a.id, a.name),
              ], filters.accountId);
              if (picked != null) onAccount(picked.$1);
            },
          ),
          const SizedBox(width: AppSpacing.sm),
          AppChip(
            label: categoryName ?? 'All categories',
            icon: Icons.sell_outlined,
            selected: categoryName != null,
            onTap: () async {
              final picked = await _pick(context, 'Category', [
                (null, 'All categories'),
                // Transactions with no category are filterable too — they
                // are the `''` bucket the dashboard breakdown also shows.
                ('', kUncategorizedLabel),
                for (final c in data.categories) (c.id, c.name),
              ], filters.categoryId);
              if (picked != null) onCategory(picked.$1);
            },
          ),
        ],
      ),
    );
  }

  /// A sheet listing [options]; resolves to the tapped one (whose id may be
  /// null for "all"), or null when dismissed.
  static Future<(String?, String)?> _pick(
    BuildContext context,
    String title,
    List<(String?, String)> options,
    String? current,
  ) {
    return showModalBottomSheet<(String?, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final c = SuiteColors.of(context);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.lg,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.smd),
                  child: Text(
                    title,
                    style: AppTextStyles.h3.copyWith(color: c.textPrimary),
                  ),
                ),
                RowGroup(
                  children: [
                    for (final o in options)
                      AppListRow(
                        title: o.$2,
                        trailing: o.$1 == current
                            ? Icon(Icons.check_rounded, color: c.accent)
                            : null,
                        onTap: () => Navigator.of(context).pop(o),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
    final c = SuiteColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.smd,
        0,
      ),
      child: Row(
        children: [
          if (filters.categoryId != null)
            Flexible(
              child: InputChip(
                avatar: const Icon(Icons.sell_outlined, size: 16),
                label: Text(
                  'Category: ${categoryFilterLabel(data, filters.categoryId!)}',
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: onClearCategory,
                deleteIconColor: c.textSecondary,
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
