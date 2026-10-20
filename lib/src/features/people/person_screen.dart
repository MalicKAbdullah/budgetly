import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
import 'package:budgetly/src/core/widgets/category_visual.dart';
import 'package:budgetly/src/features/people/person_edit.dart';
import 'package:budgetly/src/features/people/settle_sheet.dart';

/// One person: the net position, the splits behind it, and Settle up.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({required this.personKey, super.key});

  final String personKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull ?? const AppData();
    final position = PeopleLedger.forKey(data, personKey);
    if (position == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Person')),
        body: const Center(child: Text('Nothing recorded with this person.')),
      );
    }
    final code = data.currencyCode;
    final person = data.personById(position.personId);

    return Scaffold(
      appBar: AppBar(
        title: Text(position.name),
        actions: [
          if (person != null)
            IconButton(
              onPressed: () => showRenamePersonDialog(context, ref, person),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename',
            ),
        ],
      ),
      bottomNavigationBar: position.isClear
          ? null
          : BottomActionBar(
              primary: VaultButton(
                label: 'Settle up',
                icon: Icons.handshake_outlined,
                onPressed: () => showSettleSheet(context, ref, position),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          _NetCard(position: position, code: code),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            title: 'They owe you',
            entries: position.openEntries(DebtKind.owedToYou),
            data: data,
          ),
          _Section(
            title: 'You owe them',
            entries: position.openEntries(DebtKind.youOwe),
            data: data,
          ),
          if (position.settlements.isNotEmpty) ...[
            const SectionHeader(title: 'Settlements'),
            RowGroup(
              children: [
                for (final t in position.settlements)
                  TxnTile(
                    txn: t,
                    data: data,
                    onTap: () => context.push('/txn/${t.id}'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: SuiteColors.of(context).textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'A settlement clears the oldest debt first. It moves real '
                  'cash in or out of the account you pick, but never counts '
                  'as income or spending.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: SuiteColors.of(context).textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetCard extends StatelessWidget {
  const _NetCard({required this.position, required this.code});

  final PersonPosition position;
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final name = position.name;
    final netMinor = position.netMinor;
    final (line, color) = switch (netMinor) {
      > 0 => ('$name owes you', c.positive),
      < 0 => ('You owe $name', c.negative),
      _ => ('Settled up', c.textSecondary),
    };
    final owed = position
        .openEntries(DebtKind.owedToYou)
        .fold<int>(0, (s, e) => s + e.outstandingMinor);
    final owe = position
        .openEntries(DebtKind.youOwe)
        .fold<int>(0, (s, e) => s + e.outstandingMinor);
    final trimmed = name.trim();
    return VaultCard(
      radius: AppSpacing.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                monogram: trimmed.isEmpty ? '?' : trimmed[0].toUpperCase(),
                color: netMinor == 0 ? null : color,
                size: 44,
              ),
              const SizedBox(width: AppSpacing.smd),
              Expanded(
                child: Text(
                  line,
                  maxLines: 2,
                  style: AppTextStyles.label.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AmountText(
            netMinor.abs(),
            code: code,
            style: AppTextStyles.numberLarge.copyWith(fontSize: 44),
            color: netMinor == 0 ? null : color,
          ),
          if (owed > 0 && owe > 0) ...[
            const SizedBox(height: AppSpacing.mdl),
            Divider(height: 1, color: c.hairline),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'They owe you',
                    value: Money.format(owed, code: code),
                    dotColor: c.positive,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'You owe them',
                    value: Money.format(owe, code: code),
                    dotColor: c.negative,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.entries,
    required this.data,
  });

  final String title;
  final List<DebtEntry> entries;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final code = data.currencyCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          RowGroup(
            children: [
              for (final e in entries)
                AppListRow(
                  onTap: () => context.push('/txn/${e.txn.id}'),
                  leading: IconBadge(
                    icon: CategoryVisual.icon(_category(e)),
                    color: CategoryVisual.color(context, _category(e)),
                  ),
                  title: _label(e),
                  subtitle:
                      '${DateFormat.MMMd().format(e.txn.date)} · '
                      '${Money.format(e.originalMinor, code: code)} split'
                      '${e.settledMinor > 0 ? ' · ${Money.format(e.settledMinor, code: code)} settled' : ''}',
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: AmountText(
                      e.outstandingMinor,
                      code: code,
                      style: AppTextStyles.number,
                      alignment: AlignmentDirectional.centerEnd,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _category(DebtEntry e) =>
      data.categoryById(e.txn.categoryId)?.name ?? _label(e);

  String _label(DebtEntry e) => e.txn.note.isNotEmpty
      ? e.txn.note
      : data.categoryById(e.txn.categoryId)?.name ?? 'Expense';
}
