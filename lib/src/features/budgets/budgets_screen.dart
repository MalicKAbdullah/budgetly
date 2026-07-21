import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally/src/core/logic/budgets.dart';
import 'package:tally/src/core/models/category.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';
import 'package:uuid/uuid.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? c) async {
    final result = await Navigator.of(context).push<Category>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CategoryForm(existing: c),
      ),
    );
    if (result != null) {
      await ref.read(appDataProvider.notifier).saveCategory(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final code = data?.currencyCode ?? 'PKR';
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final rows = data == null
        ? <CategorySpend>[]
        : Budgets.byCategory(data, month);
    final uncategorized = data == null
        ? 0
        : Budgets.uncategorizedSpentMinor(data, month);
    final warn = AppColors.warning(Theme.of(context).brightness);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Category'),
      ),
      body: rows.isEmpty && uncategorized == 0
          ? const Center(
              child: Text(
                'Add categories to track budgets — use the + button.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                96,
              ),
              children: [
                for (final c in rows)
                  Card(
                    child: ListTile(
                      title: Text(c.name),
                      subtitle: c.hasBudget
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: LinearProgressIndicator(
                                value: c.progress,
                                color: c.overBudget ? warn : null,
                              ),
                            )
                          : const Text('No budget set'),
                      trailing: Text(
                        c.hasBudget
                            ? '${Money.format(c.spentMinor, code: code)} / ${Money.format(c.budgetMinor, code: code)}'
                            : Money.format(c.spentMinor, code: code),
                        style: TextStyle(color: c.overBudget ? warn : null),
                      ),
                      onTap: () => _edit(
                        context,
                        ref,
                        data!.categories.firstWhere(
                          (x) => x.id == c.categoryId,
                        ),
                      ),
                      onLongPress: () => ref
                          .read(appDataProvider.notifier)
                          .deleteCategory(c.categoryId),
                    ),
                  ),
                if (uncategorized > 0)
                  Card(
                    child: ListTile(
                      title: const Text('Uncategorized'),
                      trailing: Text(Money.format(uncategorized, code: code)),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'Tap to edit · long-press to delete.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.existing});
  final Category? existing;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _name;
  late final TextEditingController _budget;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _budget = TextEditingController(
      text: e == null || e.monthlyBudgetMinor == 0
          ? ''
          : (e.monthlyBudgetMinor / 100).toStringAsFixed(
              e.monthlyBudgetMinor % 100 == 0 ? 0 : 2,
            ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final budget = Money.parse(_budget.text) ?? 0;
    final e = widget.existing;
    final category = e == null
        ? Category(
            id: const Uuid().v4(),
            name: name,
            monthlyBudgetMinor: budget,
            createdAt: DateTime.now(),
          )
        : e.copyWith(name: name, monthlyBudgetMinor: budget);
    Navigator.pop(context, category);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New category' : 'Edit category'),
        actions: [TextButton(onPressed: _submit, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _budget,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monthly budget (optional)',
              helperText: 'Leave blank to just track spending',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Save category')),
        ],
      ),
    );
  }
}
