import 'package:budgetly/src/features/transactions/transactions_screen.dart';
import 'package:budgetly/src/features/transactions/txn_editor_screen.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';
import 'gallery_support.dart';

void main() {
  testWidgets('activity', (tester) async {
    await renderScreen(
      tester,
      'activity',
      () => const TransactionsScreen(),
      data: galleryData(),
      height: 1400,
    );
  }, skip: galleryOut == null);

  testWidgets('new transaction', (tester) async {
    await renderScreen(
      tester,
      'txn-new',
      () => const _Loaded(TxnEditorScreen()),
      data: galleryData(),
      height: 900,
      interact: (tester) async {
        await tester.enterText(find.byType(TextField).first, '2350');
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  }, skip: galleryOut == null);

  testWidgets('edit a split transaction', (tester) async {
    await renderScreen(
      tester,
      'txn-edit-split',
      () => const _Loaded(TxnEditorScreen(txnId: 'dinner')),
      data: galleryData(),
      height: 1500,
    );
  }, skip: galleryOut == null);
}

/// The editor reads the vault once in initState, as it does in the app where
/// the data is long loaded by the time it opens; wait for it the same way.
class _Loaded extends ConsumerWidget {
  const _Loaded(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(appDataProvider).hasValue ? child : const SizedBox.shrink();
}
