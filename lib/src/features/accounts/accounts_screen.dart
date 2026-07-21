import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally/src/core/logic/balances.dart';
import 'package:tally/src/core/models/account.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';
import 'package:uuid/uuid.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Account? existing,
  ) async {
    final result = await showDialog<Account>(
      context: context,
      builder: (_) => _AccountDialog(existing: existing),
    );
    if (result != null) {
      await ref.read(appDataProvider.notifier).saveAccount(result);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Account a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${a.name}?'),
        content: const Text(
          'This also deletes every transaction in this account. '
          'To keep history, archive it instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(appDataProvider.notifier).deleteAccount(a.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => _edit(context, ref, null),
            icon: const Icon(Icons.add),
            tooltip: 'Add account',
          ),
        ],
      ),
      body: accounts.isEmpty
          ? const Center(child: Text('No accounts yet. Tap + to add one.'))
          : ListView(
              children: [
                for (final a in accounts)
                  ListTile(
                    leading: Icon(switch (a.type) {
                      AccountType.cash => Icons.payments_outlined,
                      AccountType.bank => Icons.account_balance_outlined,
                      AccountType.wallet =>
                        Icons.account_balance_wallet_outlined,
                      AccountType.card => Icons.credit_card_outlined,
                    }),
                    title: Text(a.name + (a.archived ? '  (archived)' : '')),
                    subtitle: Text(a.type.label),
                    trailing: Text(
                      Money.format(
                        Balances.accountBalanceMinor(data!, a.id),
                        code: data.currencyCode,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () => _edit(context, ref, a),
                    onLongPress: () => _delete(context, ref, a),
                  ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
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

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.existing});
  final Account? existing;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _name;
  late final TextEditingController _opening;
  late AccountType _type;
  late bool _archived;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _opening = TextEditingController(
      text: e == null || e.openingBalanceMinor == 0
          ? ''
          : (e.openingBalanceMinor / 100).toStringAsFixed(
              e.openingBalanceMinor % 100 == 0 ? 0 : 2,
            ),
    );
    _type = e?.type ?? AccountType.cash;
    _archived = e?.archived ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final opening = Money.parse(_opening.text) ?? 0;
    final e = widget.existing;
    final account = e == null
        ? Account(
            id: const Uuid().v4(),
            name: name,
            type: _type,
            openingBalanceMinor: opening,
            createdAt: DateTime.now(),
          )
        : e.copyWith(
            name: name,
            type: _type,
            openingBalanceMinor: opening,
            archived: _archived,
          );
    Navigator.pop(context, account);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New account' : 'Edit account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<AccountType>(
            isExpanded: true,
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final t in AccountType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Opening balance'),
          ),
          if (widget.existing != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Archived'),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
