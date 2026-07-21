import 'package:core_lock/core_lock.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:budgetly/src/app.dart';
import 'package:budgetly/src/core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read the lock flag before the first frame so the app opens already locked.
  const storage = SecureStorageImpl(FlutterSecureStorage());
  final lockEnabled = await LockController.readEnabled(
    storage,
    'budgetly_app_lock_enabled',
  );

  runApp(
    ProviderScope(
      overrides: [
        deviceAuthProvider.overrideWithValue(LocalAuthDeviceAuth()),
        appLockEnabledOnLaunchProvider.overrideWithValue(lockEnabled),
      ],
      child: const BudgetlyApp(),
    ),
  );
}
