import 'dart:async';
import 'dart:developer' as developer;

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
  final startup = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  // One bulk secure-storage read serves every launch read (lock flags, date
  // filter, data key, preferences). Budgetly is the only writer of its keys
  // and holds the data key in memory for the session anyway.
  final storage = await CachedSecureStorage.load(
    const SecureStorageImpl(FlutterSecureStorage()),
  );
  const lockKey = 'budgetly_app_lock_enabled';
  // Read before the first frame so the app opens already locked (no
  // unlocked flash on cold start).
  final lockEnabled = await LockController.readEnabled(storage, lockKey);
  final biometricEnabled = await LockController.readBiometricEnabled(
    storage,
    lockKey,
  );
  // The date window the owner last chose, so every screen opens on it.
  final periodFilter = await PeriodFilterStore.read(storage);
  developer.log(
    'secure storage ready ${startup.elapsedMilliseconds} ms',
    name: 'budgetly.startup',
  );

  // Local notifications (budget alerts + monthly summary). Set up after the
  // first frame is scheduled; LocalNotify queues calls until it is ready.
  final notify = LocalNotify();

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        deviceAuthProvider.overrideWithValue(LocalAuthDeviceAuth()),
        appLockEnabledOnLaunchProvider.overrideWithValue(lockEnabled),
        appLockBiometricOnLaunchProvider.overrideWithValue(biometricEnabled),
        periodFilterOnLaunchProvider.overrideWithValue(periodFilter),
        notifyProvider.overrideWithValue(notify),
      ],
      child: const BudgetlyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback(
    (_) => developer.log(
      'first frame ${startup.elapsedMilliseconds} ms',
      name: 'budgetly.startup',
    ),
  );
  // Tapping a notification just opens the app; the dashboard handles routing.
  unawaited(
    notify
        .initialize(channels: BudgetNotifier.channels, onSelect: (_) {})
        .then((_) => notify.requestPermission()),
  );
}
