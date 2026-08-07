import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';

/// "Who owes who" across everyone the owner has split something with, in one
/// place. Tapping a person opens their transactions and the Settle action.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull ?? const AppData();
    final code = data.currencyCode;
    final open = PeopleLedger.openPositions(data);
    final settled = PeopleLedger.positions(
      data,
    ).where((p) => p.isClear).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: open.isEmpty && settled.isEmpty
          ? const _Empty()
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _TotalsCard(
                  owedToYouMinor: PeopleLedger.totalOwedToYouMinor(data),
                  youOweMinor: PeopleLedger.totalYouOweMinor(data),
                  code: code,
                ),
                const SizedBox(height: AppSpacing.md),
                if (open.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text('Everyone is square. Nothing to settle.'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final p in open)
                          PersonRow(
                            position: p,
                            code: code,
                            onTap: () => context.push(_route(p)),
                          ),
                      ],
                    ),
                  ),
                if (settled.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Settled up',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Column(
                      children: [
                        for (final p in settled)
                          PersonRow(
                            position: p,
                            code: code,
                            onTap: () => context.push(_route(p)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

String _route(PersonPosition p) => '/people/${PeopleLedger.routeKeyFor(p.key)}';

/// One person's net position: who owes who, and how much.
class PersonRow extends StatelessWidget {
  const PersonRow({
    required this.position,
    required this.code,
    this.onTap,
    super.key,
  });

  final PersonPosition position;
  final String code;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = position.netMinor;
    final owedColor = scheme.primary;
    final oweColor = AppColors.warning(Theme.of(context).brightness);
    final (line, color) = switch (net) {
      > 0 => ('${position.name} owes you', owedColor),
      < 0 => ('You owe ${position.name}', oweColor),
      _ => ('Settled up', scheme.onSurfaceVariant),
    };

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          _initial(position.name),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(position.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: net == 0
          ? Icon(Icons.check, color: scheme.onSurfaceVariant)
          : Text(
              Money.format(net.abs(), code: code),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
    required this.code,
  });

  final int owedToYouMinor;
  final int youOweMinor;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = AppColors.warning(Theme.of(context).brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            _Half(
              label: 'Owed to you',
              value: Money.format(owedToYouMinor, code: code),
              color: scheme.primary,
            ),
            _Half(
              label: 'You owe',
              value: Money.format(youOweMinor, code: code),
              color: warn,
            ),
          ],
        ),
      ),
    );
  }
}

class _Half extends StatelessWidget {
  const _Half({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'Nobody here yet. When you add an expense and split it — either '
          '"they owe me back" or "someone paid for me" — that person shows up '
          'here until you settle up.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
