import 'dart:io';

import 'package:core_backup/core_backup.dart';
import 'package:core_theme/core_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally/src/core/providers.dart';
import 'package:tally/src/features/backup/backup_codec.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Accounts'),
                  subtitle: const Text('Cash, bank, wallets'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/accounts'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: const Text('Recurring'),
                  subtitle: const Text('Salary, rent, subscriptions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/recurring'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sms_outlined),
                  title: const Text('Import from message'),
                  subtitle: const Text('Paste a bank SMS / wallet alert'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/import'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Automatic backup',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: AutoBackupSection(
              service: ref.watch(autoBackupServiceProvider),
              producer: ref.watch(tallyBackupProducerProvider),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Restore from backup'),
              subtitle: const Text('Replace all data with a .tallybackup file'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _restore(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Tally is offline and private. Your data is encrypted on this '
                'device; backups are encrypted with your passphrase before they '
                'ever reach a folder or Drive.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(withData: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;

    final passphrase = await _askPassphrase(context);
    if (passphrase == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final raw = await File(path).readAsString();
      final data = await ref
          .read(backupCodecProvider)
          .decode(raw: raw, passphrase: passphrase);
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Replace all data?'),
          content: Text(
            'This backup has ${data.accounts.length} accounts and '
            '${data.txns.length} transactions. It will replace everything '
            'currently in Tally.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (confirm ?? false) {
        await ref.read(appDataProvider.notifier).importBackup(data);
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup restored.')),
        );
      }
    } on BackupException catch (e) {
      final msg = switch (e.error) {
        BackupError.wrongPassphrase => 'Wrong passphrase.',
        BackupError.unsupportedVersion =>
          'This backup is from a newer version.',
        BackupError.invalidFormat => 'That is not a valid Tally backup.',
      };
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read the file.')),
      );
    }
  }

  Future<String?> _askPassphrase(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Backup passphrase'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }
}
