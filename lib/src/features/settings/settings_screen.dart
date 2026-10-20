import 'dart:io';

import 'package:core_backup/core_backup.dart';
import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/backup/backup_codec.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xxl,
        ),
        children: [
          const _Section('Money'),
          RowGroup(
            children: [
              SettingsTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Accounts',
                subtitle: 'Cash, bank, wallets',
                onTap: () => context.push('/accounts'),
              ),
              SettingsTile(
                icon: Icons.people_outline_rounded,
                title: 'People',
                subtitle: 'Split expenses and settling up',
                onTap: () => context.push('/people'),
              ),
              SettingsTile(
                icon: Icons.savings_outlined,
                title: 'Savings',
                subtitle: 'What has to stay put, and the target',
                onTap: () => context.push('/savings'),
              ),
              SettingsTile(
                icon: Icons.repeat_rounded,
                title: 'Recurring',
                subtitle: 'Salary, rent, subscriptions',
                onTap: () => context.push('/recurring'),
              ),
              SettingsTile(
                icon: Icons.sms_outlined,
                title: 'Captured transactions',
                subtitle: 'Review bank/wallet alerts and history',
                onTap: () => context.push('/capture'),
              ),
            ],
          ),
          const _AutoCaptureTile(),
          const _Section('Privacy & security'),
          AppLockSettings(controller: ref.watch(lockControllerProvider)),
          const _WidgetAmountsTile(),
          const _Section(
            'Automatic backup',
            subtitle:
                'Encrypted with your passphrase before it leaves Budgetly',
          ),
          VaultCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: AutoBackupSection(
              service: ref.watch(autoBackupServiceProvider),
              producer: ref.watch(budgetlyBackupProducerProvider),
              onRevealGate: () => _confirmReveal(context, ref),
            ),
          ),
          const SizedBox(height: AppSpacing.smd),
          VaultButton(
            label: 'Restore from backup',
            icon: Icons.settings_backup_restore_rounded,
            variant: VaultButtonVariant.secondary,
            onPressed: () => _restore(context, ref),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Footnote('Replaces all data with a .budgetlybackup file.'),
          const _Section('Updates'),
          const _UpdateCheckTile(),
          const SizedBox(height: AppSpacing.xl),
          const _About(),
        ],
      ),
    );
  }

  /// Guards showing the stored backup passphrase. Uses the device biometric /
  /// credential prompt when one is available, and falls back to a deliberate
  /// confirmation on devices that have none.
  Future<bool> _confirmReveal(BuildContext context, WidgetRef ref) async {
    final deviceAuth = ref.read(deviceAuthProvider);
    if (await deviceAuth.canAuthenticate()) {
      return deviceAuth.authenticate(reason: 'Show your backup passphrase');
    }
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Show passphrase?'),
        content: const Text(
          'It will appear on screen. Make sure nobody else can see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Show'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
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
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.smd),
      child: RowGroup(
        children: [
          SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: 'Auto-capture alerts',
            subtitle: _enabled
                ? 'Reading bank alerts on this device'
                : 'Needs notification access',
            trailing: Switch(
              value: _enabled,
              // Toggling either way just opens the system screen; Android
              // owns the actual grant. We re-read on resume.
              onChanged: (_) => ref.read(captureServiceProvider).openSettings(),
            ),
          ),
        ],
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
    return RowGroup(
      children: [
        SettingsTile(
          icon: Icons.system_update_alt_rounded,
          title: 'Check for updates',
          subtitle: 'On open · nothing is uploaded',
          trailing: Switch(
            value: autoCheck,
            onChanged: (v) async {
              await ref
                  .read(secureStorageProvider)
                  .write(key: updateAutoCheckKey, value: v ? 'true' : 'false');
              ref.invalidate(updateAutoCheckProvider);
              ref.invalidate(updateCheckProvider);
            },
          ),
        ),
        SettingsTile(
          icon: Icons.refresh_rounded,
          title: 'Check now',
          trailing: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _checking ? null : _checkNow,
        ),
      ],
    );
  }
}

/// Privacy switch for the home-screen widgets: off shows a masked value so a
/// glance at the home screen never reveals amounts.
class _WidgetAmountsTile extends ConsumerWidget {
  const _WidgetAmountsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    final show = ref.watch(widgetShowAmountsProvider).valueOrNull;
    if (show == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.smd),
      child: RowGroup(
        children: [
          SettingsTile(
            icon: Icons.widgets_outlined,
            title: 'Amounts on widgets',
            subtitle: 'Off shows •••• instead',
            trailing: Switch(
              value: show,
              onChanged: (v) async {
                await ref.read(homeWidgetServiceProvider).writeShowAmounts(v);
                ref.invalidate(widgetShowAmountsProvider);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings section title with the suite's spacing above it.
class _Section extends StatelessWidget {
  const _Section(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: SectionHeader(title: title, subtitle: subtitle),
  );
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: AppTextStyles.bodySmall.copyWith(
        color: SuiteColors.of(context).textTertiary,
      ),
    ),
  );
}

/// App identity, version, the privacy promise and the family endorsement.
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    return Column(
      children: [
        const SuiteAppIcon(app: SuiteApp.budgetly, size: 56),
        const SizedBox(height: AppSpacing.smd),
        Text(
          'Budgetly',
          style: AppTextStyles.h3.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => Text(
            snap.hasData ? 'Version ${snap.data!.version}' : ' ',
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Offline and private. Your data is encrypted on this device; '
            'backups are encrypted with your passphrase before they ever '
            'reach a folder or Drive.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SuiteEndorsement(),
      ],
    );
  }
}
