import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budgetly/src/core/data/period_filter_store.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/core/widgets/period_filter_bar.dart';

class _MemoryStorage implements ISecureStorage {
  final map = <String, String>{};

  @override
  Future<void> write({required String key, required String value}) async =>
      map[key] = value;

  @override
  Future<String?> read({required String key}) async => map[key];

  @override
  Future<void> delete({required String key}) async => map.remove(key);

  @override
  Future<void> deleteAll() async => map.clear();

  @override
  Future<Map<String, String>> readAll() async => Map.of(map);
}

/// Stands in for the dashboard: it owns the filter bar.
class _FirstScreen extends StatelessWidget {
  const _FirstScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const PeriodFilterBar(),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _SecondScreen()),
          ),
          child: const Text('Go to activity'),
        ),
      ],
    ),
  );
}

/// Stands in for the activity list: it only reads the shared filter.
class _SecondScreen extends ConsumerWidget {
  const _SecondScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(periodFilterProvider);
    return Scaffold(body: Center(child: Text('Showing ${filter.preset.name}')));
  }
}

void main() {
  testWidgets('a range picked on one screen applies on the other', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(storage)],
        child: const MaterialApp(home: _FirstScreen()),
      ),
    );

    // Starts on the default window — and exactly one chip says so. The
    // custom chip used to echo the active preset's label, putting a second
    // identical "This month" chip right next to the real one.
    expect(find.widgetWithText(ChoiceChip, 'This month'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Custom range'), findsOneWidget);

    final chip = find.widgetWithText(ChoiceChip, 'This year');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go to activity'));
    await tester.pumpAndSettle();

    expect(find.text('Showing thisYear'), findsOneWidget);

    // ...and it was remembered for next launch.
    expect(
      await PeriodFilterStore.read(storage),
      const PeriodFilter(PeriodPreset.thisYear),
    );
  });
}
