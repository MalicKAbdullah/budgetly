import 'package:core_lock/core_lock.dart';
import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tally/src/core/providers.dart';
import 'package:tally/src/core/router.dart';

class TallyApp extends ConsumerWidget {
  const TallyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Tally',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light, accent: AppColors.emeraldAccent),
      darkTheme: AppTheme.build(
        Brightness.dark,
        accent: AppColors.emeraldAccent,
      ),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      // App-lock cover sits above the router; the navigator stays mounted
      // underneath so unlocking restores exactly where the user was.
      builder: (context, child) => AppLockGate(
        controller: ref.watch(lockControllerProvider),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
