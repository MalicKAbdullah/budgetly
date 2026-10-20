import 'package:budgetly/src/features/accounts/accounts_screen.dart';
import 'package:budgetly/src/features/budgets/budgets_screen.dart';
import 'package:budgetly/src/features/recurring/recurring_editor_screen.dart';
import 'package:budgetly/src/features/recurring/recurring_screen.dart';
import 'package:budgetly/src/features/savings/savings_screen.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';
import 'gallery_support.dart';

void main() {
  final screens = <String, (Widget Function(), double)>{
    'budgets': (() => const BudgetsScreen(), 1200),
    'accounts': (() => const AccountsScreen(), 844),
    'savings': (() => const SavingsScreen(), 1100),
    'recurring': (() => const RecurringScreen(), 844),
    'recurring-editor': (
      () => const _Loaded(child: RecurringEditorScreen(templateId: 'r-rent')),
      844,
    ),
  };
  for (final e in screens.entries) {
    testWidgets(e.key, (tester) async {
      await renderScreen(
        tester,
        e.key,
        e.value.$1,
        data: galleryData(),
        height: e.value.$2,
      );
    }, skip: galleryOut == null);
  }
}

/// Editors read the stored data once in `initState`, as they do in the app
/// where the data is always loaded before one opens.
class _Loaded extends ConsumerWidget {
  const _Loaded({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(appDataProvider).hasValue ? child : const SizedBox.shrink();
}
