import 'package:flutter/material.dart';

// Each dialog closes through its own builder context. The screens that open
// them live inside a StatefulShellRoute branch with its own Navigator, while
// dialogs go on the root Navigator; popping with the screen's context would
// remove the screen instead of the dialog.

Future<String?> askBackupPassphrase(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Backup passphrase'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Passphrase'),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
}

Future<bool> confirmReplaceAllData(
  BuildContext context, {
  required int accountCount,
  required int txnCount,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Replace all data?'),
      content: Text(
        'This backup has $accountCount accounts and $txnCount transactions. '
        'It will replace everything currently in Budgetly.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return confirm ?? false;
}
