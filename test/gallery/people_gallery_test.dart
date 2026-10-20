import 'package:budgetly/src/features/people/people_screen.dart';
import 'package:budgetly/src/features/people/person_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';
import 'gallery_support.dart';

void main() {
  testWidgets('people', (tester) async {
    await renderScreen(
      tester,
      'people',
      () => const PeopleScreen(),
      data: galleryData(),
      height: 1000,
    );
  }, skip: galleryOut == null);

  testWidgets('person', (tester) async {
    await renderScreen(
      tester,
      'person',
      () => const PersonScreen(personKey: 'p-ali'),
      data: galleryData(),
      height: 1000,
    );
  }, skip: galleryOut == null);
}
