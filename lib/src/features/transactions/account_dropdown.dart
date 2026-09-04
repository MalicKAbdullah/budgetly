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
      decoration: InputDecoration(labelText: label),
      items: [
        for (final a in accounts)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
      ],
      onChanged: onChanged,
    );
  }
}
