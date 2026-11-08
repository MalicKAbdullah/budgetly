import 'package:budgetly/src/features/backup/restore_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Mirrors the app router: Settings is a branch of a StatefulShellRoute, so it
/// sits on a nested Navigator while dialogs open on the root one.
Future<void> _pumpShell(
  WidgetTester tester,
  Future<void> Function(BuildContext) onTap,
) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => Scaffold(body: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => onTap(context),
                        child: const Text('Settings screen'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('Settings screen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('passphrase dialog returns the passphrase and keeps the screen', (
    tester,
  ) async {
    String? result;
    await _pumpShell(
      tester,
      (c) async => result = await askBackupPassphrase(c),
    );

    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(result, 'correct horse');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Settings screen'), findsOneWidget);
  });

  testWidgets('replace confirmation returns true and keeps the screen', (
    tester,
  ) async {
    bool? result;
    await _pumpShell(
      tester,
      (c) async => result = await confirmReplaceAllData(
        c,
        accountCount: 2,
        txnCount: 40,
      ),
    );

    expect(find.textContaining('2 accounts and 40 transactions'), findsOne);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Settings screen'), findsOneWidget);
  });

  testWidgets('cancel returns false and keeps the screen', (tester) async {
    bool? result;
    await _pumpShell(
      tester,
      (c) async =>
          result = await confirmReplaceAllData(c, accountCount: 1, txnCount: 1),
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Settings screen'), findsOneWidget);
  });
}
