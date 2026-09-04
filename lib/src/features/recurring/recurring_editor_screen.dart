import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/recurring_template.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/txn_type_selector.dart';
import 'package:budgetly/src/features/transactions/savings_field.dart';
import 'package:uuid/uuid.dart';

class RecurringEditorScreen extends ConsumerStatefulWidget {
  const RecurringEditorScreen({this.templateId, super.key});
  final String? templateId;

  @override
  ConsumerState<RecurringEditorScreen> createState() => _State();
}

class _State extends ConsumerState<RecurringEditorScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _savings = SavingsDraft();
  late TxnType _type;
  late RecurringInterval _interval;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late DateTime _start;
  RecurringTemplate? _existing;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = ref.read(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    final e = widget.templateId == null
        ? null
        : data?.recurringTemplates
              .where((t) => t.id == widget.templateId)
              .firstOrNull;
    _existing = e;
    if (e != null) {
      _type = e.type;
      _interval = e.interval;
      _amount.text = (e.amountMinor / 100).toStringAsFixed(
        e.amountMinor % 100 == 0 ? 0 : 2,
      );
      _accountId = e.accountId;
      _toAccountId = e.toAccountId;
      _categoryId = e.categoryId;
      _start = e.nextRunDate;
      _note.text = e.note;
      _savings.choice = SavingsChoice.forEarmark(e.savingsEffectMinor);
      final earmark = e.savingsEffectMinor;
      if (earmark != null) _savings.amount.text = Money.toInput(earmark.abs());
    } else {
      _type = TxnType.expense;
      _interval = RecurringInterval.monthly;
      _start = DateTime.now();
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _savings.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choose an account.');
      return;
    }
    if (_type == TxnType.transfer &&
        (_toAccountId == null || _toAccountId == _accountId)) {
      setState(() => _error = 'Choose a different destination account.');
      return;
    }
    final savingsProblem = _savings.validate(
      canEarmark: _canEarmark,
      flowMinor: minor,
    );
    if (savingsProblem != null) {
      setState(() => _savings.error = savingsProblem);
      return;
    }
    final template = RecurringTemplate(
      id: _existing?.id ?? const Uuid().v4(),
      type: _type,
      amountMinor: minor,
      accountId: _accountId!,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      categoryId: _type == TxnType.expense ? _categoryId : null,
      note: _note.text.trim(),
      interval: _interval,
      nextRunDate: _start,
      active: _existing?.active ?? true,
      savingsEffectMinor: _savings.earmarkFor(canEarmark: _canEarmark),
      createdAt: _existing?.createdAt ?? DateTime.now(),
    );
    await ref.read(appDataProvider.notifier).saveRecurring(template);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    await ref.read(appDataProvider.notifier).deleteRecurring(_existing!.id);
    if (mounted) context.pop();
  }

  /// A transfer between the owner's own accounts never changes how much is
  /// reserved, so it has nothing to earmark.
  bool get _canEarmark => _type != TxnType.transfer;

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    final categories = data?.categories ?? const <Category>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New recurring' : 'Edit recurring'),
        actions: [
          if (_existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: accounts.isEmpty
          ? const Center(child: Text('Add an account first (Settings).'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                TxnTypeSelector(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '${data?.currencyCode ?? 'PKR'} ',
                    errorText: _error,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: _type == TxnType.transfer
                        ? 'From account'
                        : 'Account',
                  ),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ],
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                if (_type == TxnType.transfer) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _toAccountId,
                    decoration: const InputDecoration(labelText: 'To account'),
                    items: [
                      for (final a in accounts)
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (v) => setState(() => _toAccountId = v),
                  ),
                ],
                if (_type == TxnType.expense) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      for (final c in categories)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<RecurringInterval>(
                  isExpanded: true,
                  initialValue: _interval,
                  decoration: const InputDecoration(labelText: 'Repeats'),
                  items: [
                    for (final i in RecurringInterval.values)
                      DropdownMenuItem(value: i, child: Text(i.label)),
                  ],
                  onChanged: (v) => setState(() => _interval = v ?? _interval),
                ),
                if (_canEarmark) ...[
                  const SizedBox(height: AppSpacing.md),
                  SavingsField(
                    choice: _savings.choice,
                    amount: _savings.amount,
                    categoryEffect:
                        data?.categoryById(_categoryId)?.savingsEffect ??
                        SavingsEffect.none,
                    flowMinor: Money.parse(_amount.text) ?? 0,
                    code: data?.currencyCode ?? 'PKR',
                    errorText: _savings.error,
                    onChoice: (c) => setState(() {
                      _savings.choice = c;
                      _savings.error = null;
                    }),
                    onChanged: () => setState(() => _savings.error = null),
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Starts / next run'),
                  trailing: Text(DateFormat.yMMMd().format(_start)),
                  onTap: _pickStart,
                ),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
    );
  }
}
