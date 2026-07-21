import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally/src/core/providers.dart';
import 'package:tally/src/features/dashboard/dashboard_screen.dart'
    show TxnTile;

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.txns.isEmpty) {
            return const Center(
              child: Text('No transactions yet. Tap + to add one.'),
            );
          }
          final txns = [...data.txns]..sort((a, b) => b.date.compareTo(a.date));
          return ListView.separated(
            itemCount: txns.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => TxnTile(
              txn: txns[i],
              data: data,
              onTap: () => context.push('/txn/${txns[i].id}'),
            ),
          );
        },
      ),
    );
  }
}
