import 'package:budgetly/src/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';
import 'gallery_support.dart';

void main() {
  testWidgets('home', (tester) async {
    await renderScreen(
      tester,
      'home',
      () => const DashboardScreen(),
      data: galleryData(),
      height: 3500,
    );
  }, skip: galleryOut == null);

  // The phone's first screen, then two scrolled screens below it.
  for (final (i, offset) in [(1, 0.0), (2, 760.0), (3, 1520.0), (4, 2280.0)]) {
    testWidgets('home screen $i', (tester) async {
      await renderScreen(
        tester,
        'home-$i',
        () => const DashboardScreen(),
        data: galleryData(),
        height: 844,
        interact: (tester) async {
          if (offset == 0) return;
          for (final list in find.byType(Scrollable).evaluate().toList()) {
            final state = (list as StatefulElement).state as ScrollableState;
            if (state.axisDirection == AxisDirection.down) {
              state.position.jumpTo(offset);
            }
          }
        },
      );
    }, skip: galleryOut == null);
  }
}
