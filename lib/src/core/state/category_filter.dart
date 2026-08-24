import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one category selection shared by the dashboard breakdown and the
/// activity list: tapping a category on the dashboard opens the list already
/// narrowed to it.
///
/// The value is a category id, with two special values:
/// - `null` — no category filter, show everything.
/// - `''`   — only transactions with no category ("Uncategorized"). This is the
///   same empty-string key `DashboardFlow.spendByCategory` groups them under,
///   so a breakdown row can be handed straight to the filter.
///
/// Deliberately **session-scoped, never persisted**: the date window is a
/// standing preference the owner wanted remembered, but a category filter that
/// survived a restart would open the app on a mysteriously short list.
final categoryFilterProvider =
    NotifierProvider<CategoryFilterController, String?>(
      CategoryFilterController.new,
    );

final class CategoryFilterController extends Notifier<String?> {
  /// Every launch starts unfiltered — see the note above.
  @override
  String? build() => null;

  /// Narrows every screen to [categoryId] (`''` for uncategorized).
  void select(String? categoryId) => state = categoryId;

  void clear() => state = null;
}
