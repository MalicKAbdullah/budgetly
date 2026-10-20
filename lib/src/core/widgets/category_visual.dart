import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';

/// The icon and tint a category is drawn with. Categories store only a name,
/// so the icon comes from well-known words in it and the tint from a stable
/// hash of the name: the same category looks the same on every screen.
abstract final class CategoryVisual {
  static IconData icon(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(['grocer', 'market', 'household'])) {
      return Icons.shopping_basket_outlined;
    }
    if (has(['dining', 'food', 'restaurant', 'coffee', 'eat'])) {
      return Icons.restaurant_outlined;
    }
    if (has(['transport', 'fuel', 'car', 'taxi', 'travel', 'ride'])) {
      return Icons.directions_car_outlined;
    }
    if (has(['rent', 'housing', 'home', 'house'])) return Icons.home_outlined;
    if (has(['util', 'electric', 'bill', 'internet', 'phone', 'gas'])) {
      return Icons.bolt_outlined;
    }
    if (has(['health', 'medic', 'pharma', 'doctor', 'gym'])) {
      return Icons.favorite_border_rounded;
    }
    if (has(['saving', 'invest'])) return Icons.savings_outlined;
    if (has(['shop', 'cloth'])) return Icons.shopping_bag_outlined;
    if (has(['school', 'educat', 'book'])) return Icons.school_outlined;
    if (has(['gift', 'charity', 'donat'])) return Icons.redeem_outlined;
    if (has(['entertain', 'movie', 'fun', 'subscri'])) {
      return Icons.local_activity_outlined;
    }
    return Icons.sell_outlined;
  }

  static Color color(BuildContext context, String name) {
    final series = SuiteColors.of(context).chart;
    var h = 0;
    for (final unit in name.toLowerCase().codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return series[h % series.length];
  }
}
