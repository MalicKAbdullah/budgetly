import 'package:core_lock/core_lock.dart';
import 'package:core_notify/core_notify.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:budgetly/src/app.dart';
import 'package:budgetly/src/core/data/period_filter_store.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/notifications/budget_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read the lock flags before the first frame so the app opens already
  // locked (no unlocked flash on cold start).
  const storage = SecureStorageImpl(FlutterSecureStorage());
  const lockKey = 'budgetly_app_lock_enabled';
  final lockEnabled = await LockController.readEnabled(storage, lockKey);
  final biometricEnabled = await LockController.readBiometricEnabled(
    storage,
    lockKey,
  );

  // The date window the owner last chose, so every screen opens on it.
  final periodFilter = await PeriodFilterStore.read(storage);

  // Local notifications (budget alerts + monthly summary). Tapping just opens
  // the app; the dashboard handles routing.
  final notify = LocalNotify();
  await notify.initialize(channels: BudgetNotifier.channels, onSelect: (_) {});
  await notify.requestPermission();

  runApp(
    ProviderScope(
      overrides: [
        deviceAuthProvider.overrideWithValue(LocalAuthDeviceAuth()),
        appLockEnabledOnLaunchProvider.overrideWithValue(lockEnabled),
        appLockBiometricOnLaunchProvider.overrideWithValue(biometricEnabled),
        periodFilterOnLaunchProvider.overrideWithValue(periodFilter),
        notifyProvider.overrideWithValue(notify),
      ],
      child: const BudgetlyApp(),
    ),
  );
}
