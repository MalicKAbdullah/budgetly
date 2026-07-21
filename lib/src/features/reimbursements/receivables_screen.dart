import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/logic/reimbursements.dart';
import 'package:tally/src/core/models/account.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';

class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final code = data?.currencyCode ?? 'PKR';
    final rows = data == null ? const [] : Reimbursements.outstanding(data);
    final total = data == null ? 0 : Reimbursements.totalOwedMinor(data);

    return Scaffold(
      appBar: AppBar(title: const Text('Owed to you')),
      body: rows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Nothing outstanding. When you add an expense and mark part '
                  'as "someone owes me back", it shows up here until repaid.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Total owed to you'),
                    trailing: Text(
                      Money.format(total, code: code),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                for (final r in rows)
                  Card(
                    child: ListTile(
                      title: Text(
                        r.expense.note.isNotEmpty
                            ? r.expense.note
                            : data!.categoryById(r.expense.categoryId)?.name ??
                                  'Expense',
                      ),
                      subtitle: Text(
                        '${DateFormat.yMMMd().format(r.expense.date)} · '
                        'paid ${Money.format(r.expense.amountMinor, code: code)}',
                      ),
                      trailing: Text(
                        Money.format(r.owedMinor, code: code),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => _markRepaid(context, ref, data!, r),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'Tap an item to record a repayment.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _markRepaid(
    BuildContext context,
    WidgetRef ref,
    AppData data,
    Receivable r,
  ) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _RepayDialog(
        accounts: data.activeAccounts,
        maxMinor: r.owedMinor,
        code: data.currencyCode,
      ),
    );
    if (result != null) {
      await ref
          .read(appDataProvider.notifier)
          .markReimbursed(
            r.expense.id,
            amountMinor: result.$1,
            accountId: result.$2,
            date: DateTime.now(),
          );
    }
  }
}

class _RepayDialog extends StatefulWidget {
  const _RepayDialog({
    required this.accounts,
    required this.maxMinor,
    required this.code,
  });
  final List<Account> accounts;
  final int maxMinor;
  final String code;

  @override
  State<_RepayDialog> createState() => _RepayDialogState();
}

class _RepayDialogState extends State<_RepayDialog> {
  late final TextEditingController _amount;
  String? _accountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (widget.maxMinor / 100).toStringAsFixed(
        widget.maxMinor % 100 == 0 ? 0 : 2,
      ),
    );
    _accountId = widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Choose the account it went into.');
      return;
    }
    Navigator.pop(context, (minor, _accountId!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record repayment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received',
              prefixText: '${widget.code} ',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Into account'),
            items: [
              for (final a in widget.accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Record')),
      ],
    );
  }
}
