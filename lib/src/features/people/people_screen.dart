import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/widgets/money_text.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/people/person_edit.dart';

/// "Who owes who" across everyone the owner has split something with, in one
/// place. Tapping a person opens their transactions and the Settle action.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull ?? const AppData();
    final code = data.currencyCode;
    // Biggest open balance first: the person most worth chasing (or paying)
    // is the one the owner opened this screen for.
    final open = PeopleLedger.openPositions(data)
      ..sort((a, b) => b.netMinor.abs().compareTo(a.netMinor.abs()));
    final settled = PeopleLedger.positions(
      data,
    ).where((p) => p.isClear).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      // The empty state carries its own Add action.
      floatingActionButton: open.isEmpty && settled.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAddPersonDialog(context, ref),
              icon: const Icon(Icons.person_add_alt_rounded),
              label: const Text('Add person'),
            ),
      body: open.isEmpty && settled.isEmpty
          ? _Empty(onAdd: () => showAddPersonDialog(context, ref))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                112,
              ),
              children: [
                _TotalsCard(
                  owedToYouMinor: PeopleLedger.totalOwedToYouMinor(data),
                  youOweMinor: PeopleLedger.totalYouOweMinor(data),
                  openCount: open.length,
                  code: code,
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionHeader(
                  title: 'Open balances',
                  subtitle: open.isEmpty
                      ? null
                      : 'Biggest first · long-press to rename or remove',
                ),
                if (open.isEmpty)
                  const VaultCard(
                    child: AppEmptyState(
                      compact: true,
                      icon: Icons.handshake_outlined,
                      title: 'Everyone is square',
                      message: 'Nothing to settle.',
                    ),
                  )
                else
                  RowGroup(
                    children: [
                      for (final p in open)
                        PersonRow(
                          position: p,
                          code: code,
                          onTap: () => context.push(_route(p)),
                          onManage: () => _manage(context, ref, data, p),
                        ),
                    ],
                  ),
                if (settled.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader(title: 'No open balance'),
                  RowGroup(
                    children: [
                      for (final p in settled)
                        PersonRow(
                          position: p,
                          code: code,
                          onTap: () => context.push(_route(p)),
                          onManage: () => _manage(context, ref, data, p),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

String _route(PersonPosition p) => '/people/${PeopleLedger.routeKeyFor(p.key)}';

/// Rename / delete, offered only for a registry person — the "Unspecified"
/// bucket is not a record and has nothing to rename.
Future<void> _manage(
  BuildContext context,
  WidgetRef ref,
  AppData data,
  PersonPosition position,
) async {
  final person = data.personById(position.personId);
  if (person == null) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xs),
          AppListRow(
            leading: const IconBadge(icon: Icons.edit_outlined),
            title: 'Rename ${person.name}',
            onTap: () {
              Navigator.pop(sheetContext);
              showRenamePersonDialog(context, ref, person);
            },
          ),
          AppListRow(
            leading: IconBadge(
              icon: Icons.delete_outline_rounded,
              color: SuiteColors.of(sheetContext).negative,
            ),
            title: 'Delete',
            onTap: () {
              Navigator.pop(sheetContext);
              confirmDeletePerson(context, ref, person);
            },
          ),
        ],
      ),
    ),
  );
}

/// One person's net position: who owes who, and how much.
class PersonRow extends StatelessWidget {
  const PersonRow({
    required this.position,
    required this.code,
    this.onTap,
    this.onManage,
    super.key,
  });

  final PersonPosition position;
  final String code;
  final VoidCallback? onTap;

  /// Long-press action: rename or delete. Absent where the row is read-only
  /// (the dashboard).
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final net = position.netMinor;
    final (line, color) = switch (net) {
      > 0 => ('Owes you', c.positive),
      < 0 => ('You owe them', c.negative),
      _ => ('Settled up', null),
    };

    return AppListRow(
      onTap: onTap,
      onLongPress: onManage,
      leading: IconBadge(monogram: _initial(position.name), color: color),
      title: position.name,
      subtitle: line,
      showChevron: net == 0,
      trailing: net == 0
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: AmountText(
                net.abs(),
                code: code,
                style: AppTextStyles.number,
                color: color,
                alignment: AlignmentDirectional.centerEnd,
              ),
            ),
    );
  }

  static String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.owedToYouMinor,
    required this.youOweMinor,
    required this.openCount,
    required this.code,
  });

  final int owedToYouMinor;
  final int youOweMinor;
  final int openCount;
  final String code;

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final net = owedToYouMinor - youOweMinor;
    Widget side(String label, int minor, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AmountText(minor, code: code, style: AppTextStyles.numberMedium),
      ],
    );
    return VaultCard(
      radius: AppSpacing.radiusXl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            net >= 0 ? 'Net owed to you' : 'Net you owe',
            style: AppTextStyles.label.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          AmountText(
            net.abs(),
            code: code,
            style: AppTextStyles.numberLarge.copyWith(fontSize: 44),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            openCount == 0
                ? 'Nobody has an open balance'
                : openCount == 1
                ? 'Across 1 person'
                : 'Across $openCount people',
            style: AppTextStyles.bodySmall.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.mdl),
          Divider(height: 1, color: c.hairline),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: side('Owed to you', owedToYouMinor, c.positive)),
              // A fixed rule: the figures measure themselves with a
              // LayoutBuilder, which cannot report an intrinsic height.
              Container(
                width: 1,
                height: 48,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                color: c.hairline,
              ),
              Expanded(child: side('You owe', youOweMinor, c.negative)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: AppEmptyState(
          icon: Icons.group_outlined,
          title: 'Nobody here yet',
          message:
              'Add the people you share bills with, then split an expense — '
              'either "they owe me back" or "someone paid for me" — and '
              'their balance shows up here until you settle up. '
              'Long-press anyone to rename or remove them.',
          action: VaultButton(
            label: 'Add person',
            icon: Icons.person_add_alt_rounded,
            isFullWidth: false,
            onPressed: onAdd,
          ),
        ),
      ),
    );
  }
}
