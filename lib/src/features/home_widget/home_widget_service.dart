import 'package:core_storage/core_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:budgetly/src/features/home_widget/widget_snapshot.dart';

/// Pushes a [WidgetSnapshot] to the Android home-screen widgets.
class HomeWidgetService {
  HomeWidgetService(this._storage);

  final ISecureStorage _storage;

  /// Whether widgets show real amounts. On unless the owner turned it off.
  static const String showAmountsKey = 'budgetly_widget_show_amounts';

  static const _providers = [
    'dev.abdullah.budgetly.LeftWidgetProvider',
    'dev.abdullah.budgetly.OverviewWidgetProvider',
  ];

  Future<bool> readShowAmounts() async =>
      await _storage.read(key: showAmountsKey) != 'false';

  Future<void> writeShowAmounts(bool value) =>
      _storage.write(key: showAmountsKey, value: value ? 'true' : 'false');

  Future<void> push(WidgetSnapshot s) async {
    final values = <String, Object>{
      'month': s.monthLabel,
      'primary_label': s.primaryLabel,
      'primary_value': s.primaryValue,
      'spent_value': s.spentValue,
      'budget_value': s.budgetValue,
      'progress': s.progressPercent,
      'show_bar': s.showBar,
      'over_budget': s.overBudget,
      'owed_value': s.owedValue,
      for (var i = 0; i < 3; i++) ...{
        'cat${i}_name': i < s.categories.length ? s.categories[i].name : '',
        'cat${i}_amount': i < s.categories.length
            ? s.categories[i].amount
            : '',
      },
    };
    for (final e in values.entries) {
      await HomeWidget.saveWidgetData<Object>(e.key, e.value);
    }
    for (final name in _providers) {
      await HomeWidget.updateWidget(qualifiedAndroidName: name);
    }
  }
}
