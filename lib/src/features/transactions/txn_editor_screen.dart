import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
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
import 'package:budgetly/src/core/widgets/txn_type_selector.dart';
import 'package:budgetly/src/features/people/person_picker.dart';
import 'package:budgetly/src/features/transactions/account_dropdown.dart';
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

  /// A transfer never changes how much is reserved, and a settlement only
  /// passes money through — neither has anything to earmark.
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

    final c = SuiteColors.of(context);
    final gap = const SizedBox(height: AppSpacing.md);

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Add transaction' : 'Edit transaction'),
        actions: [
          if (_existing != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
            ),
        ],
      ),
      bottomNavigationBar: accounts.isEmpty
          ? null
          : BottomActionBar(
              primary: VaultButton(label: 'Save', onPressed: _save),
            ),
      body: accounts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: AppEmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No account yet',
                  message: 'Add an account first (Settings).',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              children: [
                if (!_isSettlement)
                  TxnTypeSelector(
                    value: _type,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                const SizedBox(height: AppSpacing.xl),
                _AmountEntry(
                  controller: _amount,
                  label: _splitOn ? 'Amount you paid' : 'Amount',
                  currency: Money.symbol(code).trim(),
                  autofocus: _existing == null,
                  error: _error,
                  onChanged: () => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpacing.xl),
                VaultCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AccountDropdown(
                        label: _type == TxnType.transfer
                            ? 'From account'
                            : 'Account',
                        accounts: accounts,
                        value: _accountId,
                        onChanged: (v) => setState(() => _accountId = v),
                      ),
                      if (_type == TxnType.transfer) ...[
                        gap,
                        AccountDropdown(
                          label: 'To account',
                          accounts: accounts,
                          value: _toAccountId,
                          onChanged: (v) => setState(() => _toAccountId = v),
                        ),
                      ],
                      if (_type == TxnType.expense && !_isSettlement) ...[
                        gap,
                        DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: _categoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.sell_outlined),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Uncategorized'),
                            ),
                            for (final cat in categories)
                              DropdownMenuItem(
                                value: cat.id,
                                child: Text(cat.name),
                              ),
                          ],
                          onChanged: (v) => setState(() => _categoryId = v),
                        ),
                      ],
                      gap,
                      _DateField(date: _date, onTap: _pickDate),
                      gap,
                      AppTextField(
                        controller: _note,
                        label: 'Note (optional)',
                        prefixIcon: Icons.notes_rounded,
                      ),
                    ],
                  ),
                ),
                if (_type == TxnType.expense && !_isSettlement) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'Split'),
                  VaultCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.cardPadding,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.xs,
                          ),
                          title: Text(
                            'Split with someone',
                            style: AppTextStyles.body.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Only your share counts as your spending',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          value: _isSplit,
                          onChanged: (v) => setState(() => _isSplit = v),
                        ),
                        AnimatedSize(
                          duration: AppMotion.base,
                          curve: AppMotion.standard,
                          alignment: Alignment.topCenter,
                          child: _isSplit
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.cardPadding,
                                    AppSpacing.sm,
                                    AppSpacing.cardPadding,
                                    AppSpacing.cardPadding,
                                  ),
                                  child: SplitFields(
                                    draft: _split,
                                    nameFor: (id) =>
                                        (data ?? const AppData())
                                            .personById(id)
                                            ?.name ??
                                        PeopleLedger.unnamedLabel,
                                    paidMinor: Money.parse(_amount.text) ?? 0,
                                    code: code,
                                    onAddPerson: _addPerson,
                                    onChanged: () =>
                                        setState(() => _error = null),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ],
                if (linkCard != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  linkCard,
                ] else if (data != null && _existing != null) ...[
                  TxnSettleLinkSection(data: data, txn: _existing!),
                ],
              ],
            ),
    );
  }
}

/// The amount, set large and centred: it is the one figure the whole form is
/// about. The currency sits beside it, smaller, as on every money figure.
class _AmountEntry extends StatelessWidget {
  const _AmountEntry({
    required this.controller,
    required this.label,
    required this.currency,
    required this.autofocus,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String currency;
  final bool autofocus;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final figure = AppTextStyles.hero.copyWith(color: c.textPrimary);
    return Column(
      children: [
        Text(
          label,
          style: AppTextStyles.label.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currency,
              style: AppTextStyles.h1.copyWith(color: c.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: TextField(
                    controller: controller,
                    autofocus: autofocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    style: figure,
                    cursorColor: c.accent,
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: figure.copyWith(color: c.textTertiary),
                      filled: false,
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: AppMotion.fast,
          child: error == null
              ? const SizedBox(height: AppSpacing.sm)
              : Padding(
                  key: ValueKey(error),
                  padding: const EdgeInsets.only(top: AppSpacing.smd),
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(color: c.negative),
                  ),
                ),
        ),
      ],
    );
  }
}

/// The date, as a read-only field that opens the picker — same height and
/// look as the dropdowns beside it.
class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Semantics(
      button: true,
      label: 'Date',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Date',
            prefixIcon: Icon(Icons.calendar_today_outlined),
            suffixIcon: Icon(Icons.expand_more_rounded),
          ),
          child: Text(
            DateFormat.yMMMEd().format(date),
            style: AppTextStyles.body.copyWith(color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}
