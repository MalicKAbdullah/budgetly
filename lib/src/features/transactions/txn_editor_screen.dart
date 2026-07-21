import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:uuid/uuid.dart';

class TxnEditorScreen extends ConsumerStatefulWidget {
  const TxnEditorScreen({this.txnId, super.key});
  final String? txnId;

  @override
  ConsumerState<TxnEditorScreen> createState() => _TxnEditorScreenState();
}

class _TxnEditorScreenState extends ConsumerState<TxnEditorScreen> {
  static const _uuid = Uuid();

  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _reimbursable = TextEditingController();
  bool _split = false;
  late TxnType _type;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  late DateTime _date;
  Txn? _existing;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = ref.read(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    final existing = widget.txnId == null ? null : data?.txnById(widget.txnId!);
    _existing = existing;
    if (existing != null) {
      _type = existing.type;
      _amount.text = (existing.amountMinor / 100).toStringAsFixed(
        existing.amountMinor % 100 == 0 ? 0 : 2,
      );
      _accountId = existing.accountId;
      _toAccountId = existing.toAccountId;
      _categoryId = existing.categoryId;
      _date = existing.date;
      _note.text = existing.note;
      _split = existing.reimbursableMinor > 0;
      if (_split) {
        _reimbursable.text = (existing.reimbursableMinor / 100).toStringAsFixed(
          existing.reimbursableMinor % 100 == 0 ? 0 : 2,
        );
      }
    } else {
      _type = TxnType.expense;
      _date = DateTime.now();
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reimbursable.dispose();
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
    var reimbursable = 0;
    if (_type == TxnType.expense && _split) {
      final r = Money.parse(_reimbursable.text);
      if (r == null || r <= 0 || r > minor) {
        setState(
          () => _error = 'Owed-back amount must be between 0 and the total.',
        );
        return;
      }
      reimbursable = r;
    }
    final txn = Txn(
      id: _existing?.id ?? _uuid.v4(),
      type: _type,
      amountMinor: minor,
      date: _date,
      accountId: _accountId!,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      categoryId: _type == TxnType.expense ? _categoryId : null,
      note: _note.text.trim(),
      reimbursableMinor: reimbursable,
      createdAt: _existing?.createdAt ?? DateTime.now(),
    );
    await ref.read(appDataProvider.notifier).saveTxn(txn);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    await ref.read(appDataProvider.notifier).deleteTxn(_existing!.id);
    if (mounted) context.pop();
  }

  String _yourShareLabel(String code) {
    final total = Money.parse(_amount.text) ?? 0;
    final owed = Money.parse(_reimbursable.text) ?? 0;
    final share = (total - owed).clamp(0, total);
    return 'Your share: ${Money.format(share, code: code)}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    final categories = data?.categories ?? const <Category>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Add transaction' : 'Edit transaction'),
        actions: [
          if (_existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: accounts.isEmpty
          ? const Center(child: Text('Add an account first (Settings).'))
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SegmentedButton<TxnType>(
                  segments: const [
                    ButtonSegment(
                      value: TxnType.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment(value: TxnType.income, label: Text('Income')),
                    ButtonSegment(
                      value: TxnType.transfer,
                      label: Text('Transfer'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _amount,
                  autofocus: _existing == null,
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
                _AccountDropdown(
                  label: _type == TxnType.transfer ? 'From account' : 'Account',
                  accounts: accounts,
                  value: _accountId,
                  onChanged: (v) => setState(() => _accountId = v),
                ),
                if (_type == TxnType.transfer) ...[
                  const SizedBox(height: AppSpacing.md),
                  _AccountDropdown(
                    label: 'To account',
                    accounts: accounts,
                    value: _toAccountId,
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Someone owes me back'),
                    subtitle: const Text(
                      'Track the part friends will repay you',
                    ),
                    value: _split,
                    onChanged: (v) => setState(() => _split = v),
                  ),
                  if (_split) ...[
                    TextField(
                      controller: _reimbursable,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount owed back to you',
                        prefixText: '${data?.currencyCode ?? 'PKR'} ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _yourShareLabel(data?.currencyCode ?? 'PKR'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Date'),
                  trailing: Text(DateFormat.yMMMd().format(_date)),
                  onTap: _pickDate,
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

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }
}
