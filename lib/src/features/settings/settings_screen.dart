import 'dart:io';

import 'package:core_backup/core_backup.dart';
import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/backup/backup_codec.dart';

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
                  title: const Text('Auto-capture & import'),
                  subtitle: const Text('Read bank/wallet alerts, or paste one'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/import'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _AutoCaptureTile(),
          const SizedBox(height: AppSpacing.md),
          Text('Security', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          AppLockSettings(controller: ref.watch(lockControllerProvider)),
          const SizedBox(height: AppSpacing.md),
          Text('Updates', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          const _UpdateCheckTile(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Automatic backup',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: AutoBackupSection(
              service: ref.watch(autoBackupServiceProvider),
              producer: ref.watch(budgetlyBackupProducerProvider),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Restore from backup'),
              subtitle: const Text(
                'Replace all data with a .budgetlybackup file',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _restore(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text(
                'Budgetly is offline and private. Your data is encrypted on this '
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
            'currently in Budgetly.',
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
        BackupError.invalidFormat => 'That is not a valid Budgetly backup.',
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

/// Auto-capture status: shows whether Budgetly has notification access and opens
/// the system settings to grant it. Android only — hidden elsewhere.
class _AutoCaptureTile extends ConsumerStatefulWidget {
  const _AutoCaptureTile();

  @override
  ConsumerState<_AutoCaptureTile> createState() => _AutoCaptureTileState();
}

class _AutoCaptureTileState extends ConsumerState<_AutoCaptureTile>
    with WidgetsBindingObserver {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after returning from the system settings screen.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await ref.read(captureServiceProvider).isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.read(captureServiceProvider).supported) {
      return const SizedBox.shrink();
    }
    return Card(
      child: SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Auto-capture from notifications'),
        subtitle: Text(
          _enabled
              ? 'Reading bank/wallet alerts on-device. Confirm them in import.'
              : 'Grant notification access so Budgetly can read transaction alerts',
        ),
        value: _enabled,
        onChanged: (_) async {
          // Toggling either way just opens the system screen; Android owns
          // the actual grant. We re-read on resume.
          await ref.read(captureServiceProvider).openSettings();
        },
      ),
    );
  }
}

/// "Check for updates on open" toggle + a manual "Check now" action, backed by
/// core_update. On by default; the only network call the app makes.
class _UpdateCheckTile extends ConsumerStatefulWidget {
  const _UpdateCheckTile();

  @override
  ConsumerState<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends ConsumerState<_UpdateCheckTile> {
  bool _checking = false;

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final info = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    if (info == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Update available · v${info.version}'),
          action: SnackBarAction(
            label: 'Update',
            onPressed: () => ref.read(updateServiceProvider).openDownload(info),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoCheck = ref.watch(updateAutoCheckProvider).valueOrNull ?? true;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.system_update_alt),
            title: const Text('Check for updates on open'),
            subtitle: const Text(
              'Looks for a new release on GitHub. Nothing is uploaded.',
            ),
            value: autoCheck,
            onChanged: (v) async {
              await ref
                  .read(secureStorageProvider)
                  .write(key: updateAutoCheckKey, value: v ? 'true' : 'false');
              ref.invalidate(updateAutoCheckProvider);
              ref.invalidate(updateCheckProvider);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Check now'),
            trailing: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkNow,
          ),
        ],
      ),
    );
  }
}
