import 'package:budgetly/src/features/dashboard/dashboard_screen.dart';
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
      height: 2600,
    );
  }, skip: galleryOut == null);
}
