import 'package:budgetly/src/features/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fixture.dart';
import 'gallery_support.dart';

void main() {
  testWidgets('settings', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Budgetly',
      packageName: 'com.example.budgetly',
      version: '0.18.0',
      buildNumber: '23',
      buildSignature: '',
    );
    await renderScreen(
      tester,
      'settings',
      () => const SettingsScreen(),
      data: galleryData(),
      height: 1900,
    );
  }, skip: galleryOut == null);
}
