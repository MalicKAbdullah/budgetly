import 'package:flutter/material.dart';

/// The app's one progress-bar look: a slim rounded track that eases to its
/// value, so a budget filling up reads as movement rather than a jump.
class ProgressBar extends StatelessWidget {
  const ProgressBar({required this.value, this.color, super.key});

  /// 0..1; values past 1 (over budget) draw a full bar.
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 6,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          color: color,
        ),
      ),
    );
  }
}
