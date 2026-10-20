import 'package:flutter/material.dart';
import 'package:budgetly/src/core/models/account.dart';

/// The account picker used by the transaction editor for both "from" and "to".
class AccountDropdown extends StatelessWidget {
  const AccountDropdown({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
    super.key,
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(_icon(accounts, value)),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }

  static IconData _icon(List<Account> accounts, String? id) {
    final type = accounts.where((a) => a.id == id).firstOrNull?.type;
    return switch (type) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.bank => Icons.account_balance_outlined,
      AccountType.wallet => Icons.account_balance_wallet_outlined,
      AccountType.card => Icons.credit_card_outlined,
      null => Icons.account_balance_outlined,
    };
  }
}
