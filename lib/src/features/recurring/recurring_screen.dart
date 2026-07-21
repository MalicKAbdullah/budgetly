import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tally/src/core/models/recurring_template.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final code = data?.currencyCode ?? 'PKR';
    final templates = data?.recurringTemplates ?? const <RecurringTemplate>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            onPressed: () => context.push('/recurring/new'),
            icon: const Icon(Icons.add),
            tooltip: 'Add recurring',
          ),
        ],
      ),
      body: templates.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Add repeating transactions like salary, rent, or '
                  'subscriptions. They post automatically when due.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final t in templates)
                  ListTile(
                    title: Text(
                      t.note.isNotEmpty
                          ? t.note
                          : data!.categoryById(t.categoryId)?.name ??
                                t.type.label,
                    ),
                    subtitle: Text(
                      '${t.interval.label} · '
                      '${t.active ? 'next ${DateFormat.yMMMd().format(t.nextRunDate)}' : 'paused'}',
                    ),
                    leading: Text(
                      Money.format(t.amountMinor, code: code),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: Switch(
                      value: t.active,
                      onChanged: (v) => ref
                          .read(appDataProvider.notifier)
                          .setRecurringActive(t.id, v),
                    ),
                    onTap: () => context.push('/recurring/${t.id}'),
                    onLongPress: () => ref
                        .read(appDataProvider.notifier)
                        .deleteRecurring(t.id),
                  ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    'Tap to edit · long-press to delete.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}
