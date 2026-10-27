import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gallery_support.dart';

final class _NoAuth implements IDeviceAuth {
  @override
  Future<bool> canAuthenticate() async => true;
  @override
  Future<bool> authenticate({required String reason}) async => false;
}

/// Stands in for Argon2 so previews are fast and deterministic.
final class _PlainHasher implements IPasswordHasher {
  @override
  Future<String> hash(String password) async => 'h:$password';
  @override
  Future<bool> verify(String password, String stored) async =>
      stored == 'h:$password';
}

final _now = DateTime(2026, 10, 20, 21, 41);
const _key = 'budgetly_app_lock_enabled';

LockController _lock({required bool biometric, Duration? cooldown}) {
  final storage = MemorySecureStorage()
    ..write(key: '${_key}_verifier', value: 'h:right')
    ..write(key: '${_key}_recovery', value: 'h:key');
  if (cooldown != null) {
    storage
      ..write(key: '${_key}_failed_attempts', value: '5')
      ..write(
        key: '${_key}_lockout_until',
        value: '${_now.add(cooldown).millisecondsSinceEpoch}',
      );
  }
  return LockController(
    deviceAuth: _NoAuth(),
    hasher: _PlainHasher(),
    storage: storage,
    clock: () => _now,
    storageKey: _key,
    appName: 'Budgetly',
    enabled: true,
    biometricEnabled: biometric,
  );
}

/// The lock as BudgetlyApp shows it: AppLockGate over the app, themed by the
/// appearance setting.
Widget Function(AppearanceController) _app({
  required bool biometric,
  Duration? cooldown,
}) => (appearance) {
  final lock = _lock(biometric: biometric, cooldown: cooldown);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(Brightness.light, accent: AppAccents.budgetly),
    darkTheme: AppTheme.build(Brightness.dark, accent: AppAccents.budgetly),
    themeMode: appearance.mode,
    builder: (context, child) => AppLockGate(
      controller: lock,
      appMark: const SuiteAppIcon(app: SuiteApp.budgetly, size: 64),
      child: child!,
    ),
    home: const Scaffold(),
  );
};

/// Taps [finder] in every pane, last pane first, so a target that goes away
/// once tapped (a link swapping its form) does not shift the next index.
Future<void> _tapAll(WidgetTester tester, Finder finder) async {
  for (var i = finder.evaluate().length - 1; i >= 0; i--) {
    await tester.tap(finder.at(i), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  Future<void> shot(
    WidgetTester tester,
    String name, {
    required bool biometric,
    Duration? cooldown,
    List<ThemeMode> modes = const [ThemeMode.light, ThemeMode.dark],
    double width = 390,
    double height = 844,
    EdgeInsets viewInsets = EdgeInsets.zero,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    await renderPanes(
      tester,
      name,
      _app(biometric: biometric, cooldown: cooldown),
      modes: modes,
      width: width,
      height: height,
      viewInsets: viewInsets,
      interact: interact,
    );
    // Disposes the lock screens so no cooldown ticker outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('lock — fingerprint on', (tester) async {
    await shot(tester, 'lock-biometric', biometric: true);
  }, skip: galleryOut == null);

  testWidgets('lock — password only', (tester) async {
    await shot(tester, 'lock-password', biometric: false);
  }, skip: galleryOut == null);

  testWidgets('lock — wrong password', (tester) async {
    await shot(
      tester,
      'lock-error',
      biometric: false,
      interact: (tester) async {
        final fields = find.byType(TextField);
        for (var i = 0; i < fields.evaluate().length; i++) {
          await tester.enterText(fields.at(i), 'nope');
        }
        await _tapAll(tester, find.text('Unlock'));
        FocusManager.instance.primaryFocus?.unfocus();
      },
    );
  }, skip: galleryOut == null);

  testWidgets('lock — cooldown', (tester) async {
    await shot(
      tester,
      'lock-cooldown',
      biometric: true,
      cooldown: const Duration(seconds: 28),
    );
  }, skip: galleryOut == null);

  testWidgets('lock — recovery form', (tester) async {
    await shot(
      tester,
      'lock-recovery',
      biometric: true,
      interact: (tester) => _tapAll(tester, find.text('Forgot password?')),
    );
  }, skip: galleryOut == null);

  testWidgets('lock — small phone', (tester) async {
    await shot(
      tester,
      'lock-small',
      biometric: true,
      modes: const [ThemeMode.light],
      width: 360,
      height: 640,
    );
  }, skip: galleryOut == null);

  testWidgets('lock — small phone, keyboard up', (tester) async {
    await shot(
      tester,
      'lock-small-keyboard',
      biometric: false,
      modes: const [ThemeMode.light],
      width: 360,
      height: 640,
      viewInsets: const EdgeInsets.only(bottom: 300),
    );
  }, skip: galleryOut == null);
}
