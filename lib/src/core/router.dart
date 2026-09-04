import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:budgetly/src/core/shell/home_shell.dart';
import 'package:budgetly/src/features/accounts/accounts_screen.dart';
import 'package:budgetly/src/features/budgets/budgets_screen.dart';
import 'package:budgetly/src/features/dashboard/dashboard_screen.dart';
import 'package:budgetly/src/features/capture/capture_screen.dart';
import 'package:budgetly/src/features/recurring/recurring_editor_screen.dart';
import 'package:budgetly/src/features/recurring/recurring_screen.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/features/people/people_screen.dart';
import 'package:budgetly/src/features/people/person_screen.dart';
import 'package:budgetly/src/features/savings/savings_screen.dart';
import 'package:budgetly/src/features/settings/settings_screen.dart';
import 'package:budgetly/src/features/transactions/transactions_screen.dart';
import 'package:budgetly/src/features/transactions/txn_editor_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, _) => const TransactionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/budgets',
                builder: (_, _) => const BudgetsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/txn/new', builder: (_, _) => const TxnEditorScreen()),
      GoRoute(
        path: '/txn/:id',
        builder: (_, state) =>
            TxnEditorScreen(txnId: state.pathParameters['id']),
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(path: '/people', builder: (_, _) => const PeopleScreen()),
      GoRoute(
        path: '/people/:key',
        builder: (_, state) => PersonScreen(
          personKey: PeopleLedger.keyFromRoute(state.pathParameters['key']!),
        ),
      ),
      GoRoute(path: '/savings', builder: (_, _) => const SavingsScreen()),
      GoRoute(path: '/recurring', builder: (_, _) => const RecurringScreen()),
      GoRoute(
        path: '/recurring/new',
        builder: (_, _) => const RecurringEditorScreen(),
      ),
      GoRoute(
        path: '/recurring/:id',
        builder: (_, state) =>
            RecurringEditorScreen(templateId: state.pathParameters['id']),
      ),
      GoRoute(path: '/capture', builder: (_, _) => const CaptureScreen()),
    ],
  );
});
