import 'package:intl/intl.dart';

/// Money is stored everywhere as an integer number of **minor units** (1/100
/// of the currency) to avoid floating-point drift. This helper formats and
/// parses it for display and input.
abstract final class Money {
  static String _symbol(String code) => switch (code) {
    'PKR' => 'Rs ',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    'AED' => 'AED ',
    'SAR' => 'SAR ',
    _ => '$code ',
  };

  /// Formats [minor] units as e.g. `Rs 1,250` (or `Rs 1,250.50` when there
  /// are cents). Negative values keep their sign.
  static String format(int minor, {String code = 'PKR'}) {
    final hasCents = minor % 100 != 0;
    final f = NumberFormat.currency(
      symbol: _symbol(code),
      decimalDigits: hasCents ? 2 : 0,
    );
    return f.format(minor / 100.0);
  }

  /// Parses user input like `1250` or `1,250.50` into minor units. Returns
  /// null when the text is not a valid non-negative amount.
  static int? parse(String text) {
    final cleaned = text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value < 0 || value.isNaN || value.isInfinite) {
      return null;
    }
    return (value * 100).round();
  }
}
