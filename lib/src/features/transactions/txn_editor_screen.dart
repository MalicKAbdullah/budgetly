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
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
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
  final _share = TextEditingController();
  final _person = TextEditingController();

  bool _split = false;
  DebtKind _splitKind = DebtKind.owedToYou;
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
    _person.text = existing.counterparty;
    _split = existing.isSplit;
    if (_split) {
      _splitKind = existing.payableMinor > 0
          ? DebtKind.youOwe
          : DebtKind.owedToYou;
      _share.text = Money.toInput(
        existing.payableMinor > 0
            ? existing.payableMinor
            : existing.reimbursableMinor,
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _share.dispose();
    _person.dispose();
    super.dispose();
  }

  bool get _isSettlement => _existing?.isSettlement ?? false;
  bool get _canSplit => _type == TxnType.expense && !_isSettlement;

  Future<void> _save() async {
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
    if (_canSplit && _split) {
      final share = Money.parse(_share.text);
      if (share == null || share <= 0) {
        setState(() => _error = 'Enter how much the split is for.');
        return;
      }
      if (_splitKind == DebtKind.owedToYou) {
        if (share > paid) {
          setState(
            () => _error = 'The part owed back cannot exceed what you paid.',
          );
          return;
        }
        reimbursable = share;
      } else {
        payable = share;
      }
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
      counterparty: _isSettlement || (_canSplit && _split)
          ? _person.text.trim()
          : '',
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
                    labelText: _canSplit && _split
                        ? 'Amount you paid'
                        : 'Amount',
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
                    value: _split,
                    onChanged: (v) => setState(() => _split = v),
                  ),
                  if (_split)
                    SplitFields(
                      kind: _splitKind,
                      onKind: (k) => setState(() => _splitKind = k),
                      person: _person,
                      share: _share,
                      knownNames: PeopleLedger.knownNames(
                        data ?? const AppData(),
                      ),
                      paidMinor: Money.parse(_amount.text) ?? 0,
                      code: code,
                      onChanged: () => setState(() {}),
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
