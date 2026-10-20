import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

/// The app's one progress-bar look: the suite bar, which eases to its value
/// and shows an over-budget overflow past 1.
class ProgressBar extends StatelessWidget {
  const ProgressBar({required this.value, this.color, this.marker, super.key});

  /// 0..1; values past 1 (over budget) draw the overflow state.
  final double value;
  final Color? color;

  /// Where "on pace" sits (0..1), e.g. the share of the month gone.
  final double? marker;

  @override
  Widget build(BuildContext context) =>
      AppProgressBar(value: value, color: color, marker: marker);
}
