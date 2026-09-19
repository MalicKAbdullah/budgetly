import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// An amount shown at the end of a row.
///
/// A bare `Text` in `ListTile.trailing` takes whatever width its digits need
/// and steals it from the title, so a long balance quietly truncates the
/// category name beside it. Capping the width and letting the figure shrink
/// inside that cap keeps both readable: the row's shape stops depending on how
/// much money the transaction happened to involve.
final class MoneyTrailing extends StatelessWidget {
  const MoneyTrailing({
    required this.amount,
    this.secondary,
    this.color,
    this.maxWidth = 132,
    super.key,
  });

  final String amount;

  /// A quieter second line, e.g. the full bill behind the owner's share.
  final String? secondary;
  final Color? color;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ValueText(
            amount,
            style: AppTextStyles.number,
            color: color,
            alignment: AlignmentDirectional.centerEnd,
          ),
          if (secondary != null) ...[
            const SizedBox(height: 2),
            ValueText(
              secondary!,
              style: AppTextStyles.caption,
              color: subtle,
              alignment: AlignmentDirectional.centerEnd,
            ),
          ],
        ],
      ),
    );
  }
}

/// An amount on the right-hand side of a `Row`, sharing the width with a label
/// on the left. [flex] is the share this figure gets; the label takes the rest.
final class MoneyCell extends StatelessWidget {
  const MoneyCell({
    required this.amount,
    this.color,
    this.style,
    this.flex = 3,
    super.key,
  });

  final String amount;
  final Color? color;
  final TextStyle? style;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: ValueText(
      amount,
      style: style ?? AppTextStyles.numberSmall,
      color: color,
      alignment: AlignmentDirectional.centerEnd,
    ),
  );
}
