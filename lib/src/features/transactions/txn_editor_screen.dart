import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/models/txn_split.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/people/person_picker.dart';
import 'package:budgetly/src/features/transactions/split_fields.dart';
import 'package:budgetly/src/features/transactions/txn_links.dart';
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
  final _split = SplitDraft();

  bool _isSplit = false;
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
    if (existing == null) {
      _type = TxnType.expense;
      _date = DateTime.now();
      _accountId = accounts.isNotEmpty ? accounts.first.id : null;
      return;
    }
    _type = existing.type;
    _amount.text = Money.toInput(existing.amountMinor);
    _accountId = existing.accountId;
    _toAccountId = existing.toAccountId;
    _categoryId = existing.categoryId;
    _date = existing.date;
    _note.text = existing.note;
    _isSplit = existing.isSplit;
    // Loads the people already on it — none for a transaction written before
    // the registry, which the editor then lets the owner name.
    if (_isSplit) _split.load(existing);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _split.dispose();
    super.dispose();
  }

  bool get _isSettlement => _existing?.isSettlement ?? false;
  bool get _canSplit => _type == TxnType.expense && !_isSettlement;
  bool get _splitOn => _canSplit && _isSplit;

  Future<void> _addPerson() async {
    final person = await showPersonPicker(context, exclude: _split.personIds);
    if (person == null) return;
    setState(() => _split.add(person.id));
  }

  Future<void> _save() async {
    final data = ref.read(appDataProvider).valueOrNull;
    final paid = Money.parse(_amount.text);
    if (paid == null) {
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
    var payable = 0;
    var splits = const <TxnSplit>[];
    var names = '';
    if (_splitOn) {
      final problem = _split.validate(paidMinor: paid);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      reimbursable = _split.reimbursableMinor;
      payable = _split.payableMinor;
      splits = _split.toSplits();
      // The names are denormalized onto the transaction so rows and search read
      // them without consulting the registry. With nobody named the existing
      // text stays as it is, so a split written before the registry never loses
      // the name it carries.
      names = splits.isEmpty
          ? _existing?.counterparty ?? ''
          : PeopleLedger.counterpartyLabel(data ?? const AppData(), splits);
    }
    // A bill somebody else fronted in full moves no cash of the owner's, so
    // zero is a legitimate amount — but only then.
    if (paid <= 0 && payable == 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    final txn = Txn(
      id: _existing?.id ?? _uuid.v4(),
      type: _type,
      amountMinor: paid,
      date: _date,
      accountId: _accountId!,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      categoryId: _type == TxnType.expense ? _categoryId : null,
      note: _note.text.trim(),
      reimbursableMinor: reimbursable,
      payableMinor: payable,
      splits: splits,
      // A settlement keeps the one person it squares up with.
      personId: _isSettlement ? _existing?.personId : null,
      counterparty: _isSettlement ? _existing?.counterparty ?? '' : names,
      settlement: _existing?.settlement ?? false,
      // Preserve the legacy repayment→expense link when editing a repayment.
      reimbursesTxnId: _existing?.reimbursesTxnId,
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
    final code = data?.currencyCode ?? 'PKR';
    final linkCard = data == null || _existing == null
        ? null
        : txnLinkCard(data, _existing!);

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
                if (!_isSettlement)
                  SegmentedButton<TxnType>(
                    segments: const [
                      ButtonSegment(
                        value: TxnType.expense,
                        label: Text('Expense'),
                      ),
                      ButtonSegment(
                        value: TxnType.income,
                        label: Text('Income'),
                      ),
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
                    labelText: _splitOn ? 'Amount you paid' : 'Amount',
                    prefixText: '$code ',
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
                if (_type == TxnType.expense && !_isSettlement) ...[
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
                    title: const Text('Split with someone'),
                    subtitle: const Text(
                      'Only your share counts as your spending',
                    ),
                    value: _isSplit,
                    onChanged: (v) => setState(() => _isSplit = v),
                  ),
                  if (_isSplit)
                    SplitFields(
                      draft: _split,
                      nameFor: (id) =>
                          (data ?? const AppData()).personById(id)?.name ??
                          PeopleLedger.unnamedLabel,
                      paidMinor: Money.parse(_amount.text) ?? 0,
                      code: code,
                      onAddPerson: _addPerson,
                      onChanged: () => setState(() => _error = null),
                    ),
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
                if (linkCard != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  linkCard,
                ],
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
