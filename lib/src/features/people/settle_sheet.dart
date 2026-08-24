import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';

/// Records a settlement with one person. The amount defaults to the whole net
/// position; whatever is entered clears that person's oldest debts first.
Future<void> showSettleSheet(
  BuildContext context,
  WidgetRef ref,
  PersonPosition position,
) async {
  final data = ref.read(appDataProvider).valueOrNull ?? const AppData();
  final accounts = data.activeAccounts;
  if (accounts.isEmpty) return;

  final net = position.netMinor;
  final kind = net >= 0 ? DebtKind.owedToYou : DebtKind.youOwe;
  final result = await showModalBottomSheet<_SettleResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SettleForm(
      position: position,
      kind: kind,
      maxMinor: net.abs(),
      accounts: accounts,
      code: data.currencyCode,
    ),
  );
  if (result == null) return;

  await ref
      .read(appDataProvider.notifier)
      .settleWithPerson(
        person: position.name == PeopleLedger.unnamedLabel ? '' : position.name,
        personId: position.personId,
        kind: kind,
        amountMinor: result.amountMinor,
        accountId: result.accountId,
        date: result.date,
      );
}

class _SettleResult {
  const _SettleResult(this.amountMinor, this.accountId, this.date);
  final int amountMinor;
  final String accountId;
  final DateTime date;
}

class _SettleForm extends StatefulWidget {
  const _SettleForm({
    required this.position,
    required this.kind,
    required this.maxMinor,
    required this.accounts,
    required this.code,
  });

  final PersonPosition position;
  final DebtKind kind;
  final int maxMinor;
  final List<Account> accounts;
  final String code;

  @override
  State<_SettleForm> createState() => _SettleFormState();
}

class _SettleFormState extends State<_SettleForm> {
  late final TextEditingController _amount;
  late String _accountId;
  late DateTime _date;
  String? _error;

  bool get _receiving => widget.kind == DebtKind.owedToYou;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: Money.toInput(widget.maxMinor));
    _accountId = widget.accounts.first.id;
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    Navigator.pop(context, _SettleResult(minor, _accountId, _date));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.position.name;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            _receiving ? '$name pays you back' : 'You pay $name back',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Clears the oldest debt first. Not counted as '
            '${_receiving ? 'income' : 'spending'}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _receiving ? 'Amount received' : 'Amount paid',
              prefixText: '${widget.code} ',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _accountId,
            decoration: InputDecoration(
              labelText: _receiving ? 'Into account' : 'From account',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final a in widget.accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? _accountId),
          ),
          const SizedBox(height: AppSpacing.md),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Settled on',
              border: OutlineInputBorder(),
            ),
            child: InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat.yMMMMd().format(_date)),
                    const Icon(Icons.calendar_today_outlined, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submit,
            child: const Text('Record settlement'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
