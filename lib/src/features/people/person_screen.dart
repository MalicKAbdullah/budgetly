import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/txn_tile.dart';
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
    final net = position.netMinor;
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
      floatingActionButton: position.isClear
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showSettleSheet(context, ref, position),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Settle up'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          96,
        ),
        children: [
          _NetCard(name: position.name, netMinor: net, code: code),
          const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.md),
            Text('Settlements', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Column(
                children: [
                  for (final t in position.settlements)
                    TxnTile(
                      txn: t,
                      data: data,
                      onTap: () => context.push('/txn/${t.id}'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              'A settlement clears the oldest debt first. It moves real cash '
              'in or out of the account you pick, but never counts as income '
              'or spending.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetCard extends StatelessWidget {
  const _NetCard({
    required this.name,
    required this.netMinor,
    required this.code,
  });

  final String name;
  final int netMinor;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = AppColors.warning(Theme.of(context).brightness);
    final (line, color) = switch (netMinor) {
      > 0 => ('$name owes you', scheme.primary),
      < 0 => ('You owe $name', warn),
      _ => ('Settled up', scheme.onSurfaceVariant),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              Money.format(netMinor.abs(), code: code),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: [
                for (final e in entries)
                  ListTile(
                    onTap: () => context.push('/txn/${e.txn.id}'),
                    title: Text(
                      e.txn.note.isNotEmpty
                          ? e.txn.note
                          : data.categoryById(e.txn.categoryId)?.name ??
                                'Expense',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${DateFormat.yMMMd().format(e.txn.date)} · '
                      '${Money.format(e.originalMinor, code: code)} split'
                      '${e.settledMinor > 0 ? ' · ${Money.format(e.settledMinor, code: code)} settled' : ''}',
                      maxLines: 2,
                    ),
                    trailing: Text(
                      Money.format(e.outstandingMinor, code: code),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
