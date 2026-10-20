import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/logic/balances.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:uuid/uuid.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Account? existing,
  ) async {
    final result = await Navigator.of(context).push<Account>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AccountForm(existing: existing),
      ),
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
    final c = SuiteColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => _edit(context, ref, null),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add account',
          ),
        ],
      ),
      body: accounts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppEmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No accounts yet',
                  message: 'No accounts yet. Tap + to add one.',
                  action: VaultButton(
                    label: 'Add account',
                    icon: Icons.add_rounded,
                    isFullWidth: false,
                    onPressed: () => _edit(context, ref, null),
                  ),
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
                VaultCard(
                  radius: AppSpacing.radiusXl,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total balance',
                        style: AppTextStyles.label.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.smd),
                      AmountText(
                        Balances.netWorthMinor(data!),
                        code: data.currencyCode,
                        style: AppTextStyles.display,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${data.activeAccounts.length} active '
                        '${data.activeAccounts.length == 1 ? 'account' : 'accounts'}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionHeader(
                  title: 'Your accounts',
                  subtitle: 'Tap to edit · long-press to delete.',
                ),
                RowGroup(
                  children: [
                    for (final a in accounts)
                      AppListRow(
                        leading: IconBadge(
                          icon: accountIcon(a.type),
                          color: a.archived ? null : c.accent,
                        ),
                        title: a.name,
                        subtitle: a.archived
                            ? '${a.type.label} · Archived'
                            : a.type.label,
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: AmountText(
                            Balances.accountBalanceMinor(data, a.id),
                            code: data.currencyCode,
                            style: AppTextStyles.number,
                            color: a.archived ? c.textTertiary : null,
                            alignment: AlignmentDirectional.centerEnd,
                          ),
                        ),
                        onTap: () => _edit(context, ref, a),
                        onLongPress: () => _delete(context, ref, a),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The glyph each account type is drawn with.
IconData accountIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bank => Icons.account_balance_outlined,
  AccountType.wallet => Icons.account_balance_wallet_outlined,
  AccountType.card => Icons.credit_card_outlined,
};

class _AccountForm extends StatefulWidget {
  const _AccountForm({this.existing});
  final Account? existing;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New account' : 'Edit account'),
        actions: [TextButton(onPressed: _submit, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          AppTextField(
            controller: _name,
            autofocus: true,
            label: 'Name',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppSegmentedControl<AccountType>(
            height: 48,
            segments: [
              for (final t in AccountType.values)
                AppSegment(value: t, label: t.label),
            ],
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _opening,
            label: 'Opening balance',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Archived'),
              subtitle: const Text('Hide from pickers, keep history'),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          VaultButton(label: 'Save account', onPressed: _submit),
        ],
      ),
    );
  }
}
