import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core_backup/core_backup.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_lock/core_lock.dart';
import 'package:core_notify/core_notify.dart';
import 'package:core_storage/core_storage.dart';
import 'package:core_theme/core_theme.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/data/app_data_notifier.dart';
import 'package:budgetly/src/core/data/period_filter_store.dart';
import 'package:budgetly/src/core/logic/activity_list.dart';
import 'package:budgetly/src/core/logic/dashboard_summary.dart';
import 'package:budgetly/src/core/models/period_filter.dart';
import 'package:budgetly/src/core/security/key_derivation.dart';
import 'package:budgetly/src/core/state/txn_filters.dart';
import 'package:budgetly/src/core/storage/data_key_store.dart';
import 'package:budgetly/src/core/storage/budgetly_store.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';
import 'package:budgetly/src/features/backup/backup_codec.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/features/capture/capture_service.dart';
import 'package:budgetly/src/features/home_widget/home_widget_service.dart';
import 'package:budgetly/src/features/home_widget/widget_snapshot.dart';
import 'package:budgetly/src/features/notifications/budget_notifier.dart';

/// Wall clock as a function. Tests override with a fixed time.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final secureStorageProvider = Provider<ISecureStorage>(
  (_) => const SecureStorageImpl(FlutterSecureStorage()),
);

final cipherServiceProvider = Provider<CipherService>(
  (_) => const CipherService(),
);

final keyDerivationProvider = Provider<IKeyDerivation>(
  (_) => const Argon2KeyDerivation(KeyDerivationService()),
);

final vaultFileProvider = Provider<IVaultFile>((_) => LocalVaultFile());

final dataKeyStoreProvider = Provider<DataKeyStore>(
  (ref) => DataKeyStore(ref.watch(secureStorageProvider)),
);

final vaultWorkerProvider = Provider<VaultWorker>((_) => Isolate.run);

final budgetlyStoreProvider = Provider<BudgetlyStore>(
  (ref) => BudgetlyStore(
    cipher: ref.watch(cipherServiceProvider),
    keyStore: ref.watch(dataKeyStoreProvider),
    file: ref.watch(vaultFileProvider),
    worker: ref.watch(vaultWorkerProvider),
  ),
);

/// The single source of truth for all app data.
final appDataProvider = AsyncNotifierProvider<AppDataNotifier, AppData>(
  AppDataNotifier.new,
);

/// The System / Light / Dark choice, loaded in main() before runApp so the
/// first frame (the lock screen included) already has the chosen theme.
final appearanceProvider = Provider<AppearanceController>(
  (_) => throw UnimplementedError('main() overrides appearanceProvider'),
);

// -- Shared date filter ----------------------------------------------------

/// The filter restored from storage before the first frame; main() overrides
/// it so the dashboard opens on the window the owner last chose.
final periodFilterOnLaunchProvider = Provider<PeriodFilter>(
  (_) => const PeriodFilter.thisMonth(),
);

/// The one date window every screen reads — dashboard, activity, statement.
final periodFilterProvider =
    NotifierProvider<PeriodFilterController, PeriodFilter>(
      PeriodFilterController.new,
    );

final class PeriodFilterController extends Notifier<PeriodFilter> {
  @override
  PeriodFilter build() => ref.read(periodFilterOnLaunchProvider);

  /// Applies the window everywhere and remembers it for next launch.
  Future<void> select(PeriodFilter filter) async {
    state = filter;
    await PeriodFilterStore.write(ref.read(secureStorageProvider), filter);
  }
}

// -- Backup ---------------------------------------------------------------

final backupCodecProvider = Provider<BackupCodec>(
  (ref) => BackupCodec(
    keyDerivation: ref.watch(keyDerivationProvider),
    cipher: ref.watch(cipherServiceProvider),
  ),
);

/// SAF folder on Android (a Google Drive folder can be picked); app-documents
/// on iOS.
final backupFolderProvider = Provider<IBackupFolder>(
  (_) =>
      Platform.isAndroid ? SafBackupFolder() : const AppDocumentsBackupFolder(),
);

final autoBackupServiceProvider = Provider<AutoBackupService>(
  (ref) => AutoBackupService(
    storage: ref.watch(secureStorageProvider),
    folder: ref.watch(backupFolderProvider),
    keyPrefix: 'budgetly',
    fileLabel: 'Budgetly',
    fileExtension: BackupCodec.fileExtension,
    now: () => ref.read(clockProvider)(),
  ),
);

// -- App lock (core_lock) -------------------------------------------------

/// Unavailable by default; main() overrides with the local_auth impl.
final deviceAuthProvider = Provider<IDeviceAuth>(
  (_) => const UnavailableDeviceAuth(),
);

/// Whether the lock / biometric were on at launch — read in main() before
/// runApp so the first frame is already locked (no unlocked flash).
final appLockEnabledOnLaunchProvider = Provider<bool>((_) => false);
final appLockBiometricOnLaunchProvider = Provider<bool>((_) => false);

/// Argon2id verifier for the app-lock fallback password.
final passwordHasherProvider = Provider<IPasswordHasher>(
  (_) => const Argon2PasswordHasher(),
);

final lockControllerProvider = ChangeNotifierProvider<LockController>(
  (ref) => LockController(
    deviceAuth: ref.watch(deviceAuthProvider),
    hasher: ref.watch(passwordHasherProvider),
    storage: ref.watch(secureStorageProvider),
    clock: () => ref.read(clockProvider)(),
    storageKey: 'budgetly_app_lock_enabled',
    appName: 'Budgetly',
    enabled: ref.watch(appLockEnabledOnLaunchProvider),
    biometricEnabled: ref.watch(appLockBiometricOnLaunchProvider),
  ),
);

/// Settings availability: whether the device has enrolled biometrics.
final deviceAuthAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(deviceAuthProvider).canAuthenticate(),
);

/// Native notification-capture bridge (Android auto-import).
final captureServiceProvider = Provider<CaptureService>(
  (_) => CaptureService(),
);

// -- In-app update (core_update) ------------------------------------------

final updateServiceProvider = Provider<IUpdateService>(
  (_) => GithubUpdateService(owner: 'MalicKAbdullah', repo: 'budgetly'),
);

/// Secure-storage key for the auto-check preference.
const String updateAutoCheckKey = 'budgetly_update_autocheck';

/// Auto-check preference (persisted; on by default). Toggle in Settings.
final updateAutoCheckProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.watch(secureStorageProvider).read(key: updateAutoCheckKey) !=
      'false',
);

/// The pending update (null when disabled, up to date, or offline).
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (!await ref.watch(updateAutoCheckProvider.future)) return null;
  return ref.watch(updateServiceProvider).check();
});

/// Session-only dismissal of the update banner.
final updateDismissedProvider = StateProvider<bool>((_) => false);

// -- Notifications (core_notify) ------------------------------------------

/// Overridden in main() with an initialized [LocalNotify].
final notifyProvider = Provider<INotify>((_) => const NoopNotify());

final budgetNotifierProvider = Provider<BudgetNotifier>(
  (ref) => BudgetNotifier(
    notify: ref.watch(notifyProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);

/// Captured notifications still awaiting review. Derived from the encrypted
/// app data (the source of truth), so it updates itself on every add/dismiss.
final pendingNoticesProvider = Provider<List<CapturedNotice>>((ref) {
  final data = ref.watch(appDataProvider).valueOrNull;
  return data?.pendingNotices ?? const [];
});

/// Produces the encrypted `.budgetlybackup` bytes for the current dataset.
final budgetlyBackupProducerProvider = Provider<BackupProducer>((ref) {
  return (passphrase) async {
    final data = ref.read(appDataProvider).valueOrNull ?? const AppData();
    final raw = await ref
        .read(backupCodecProvider)
        .encode(
          data: data,
          passphrase: passphrase!,
          createdAt: ref.read(clockProvider)(),
        );
    return Uint8List.fromList(utf8.encode(raw));
  };
});

final homeWidgetServiceProvider = Provider<HomeWidgetService>(
  (ref) => HomeWidgetService(ref.watch(secureStorageProvider)),
);

final widgetShowAmountsProvider = FutureProvider<bool>(
  (ref) => ref.watch(homeWidgetServiceProvider).readShowAmounts(),
);

/// The dashboard's figures for one calendar day. Recomputed only when the data
/// snapshot or the shared filter changes, never on a plain rebuild.
final dashboardSummaryProvider = Provider.autoDispose
    .family<DashboardSummary, DateTime>((ref, today) {
      final data = ref.watch(appDataProvider.select((a) => a.requireValue));
      final filter = ref.watch(periodFilterProvider);
      final watch = Stopwatch()..start();
      final summary = DashboardSummary.compute(data, filter, today);
      if (!kReleaseMode) {
        developer.log(
          'dashboard summary ${watch.elapsedMicroseconds / 1000} ms '
          '(${data.txns.length} txns)',
          name: 'budgetly.perf',
        );
      }
      return summary;
    });

/// What the activity list shows for one filter set and date window.
typedef ActivityQuery = ({TxnFilters filters, DateTime start, DateTime end});

/// The activity list, grouped into days. Recomputed only when the data
/// snapshot or the query changes, never on a plain rebuild.
final activityListProvider = Provider.autoDispose
    .family<ActivityList, ActivityQuery>((ref, query) {
      final data = ref.watch(appDataProvider.select((a) => a.requireValue));
      return ActivityList.of(
        data,
        query.filters,
        start: query.start,
        end: query.end,
      );
    });

/// Keeps the home-screen widgets in step with the vault: pushes a fresh
/// snapshot on app start, after every data change and when the privacy
/// toggle flips. Android only — the widgets are native RemoteViews.
final homeWidgetSyncProvider = Provider<void>((ref) {
  if (!Platform.isAndroid) return;
  final data = ref.watch(appDataProvider).valueOrNull;
  final showAmounts = ref.watch(widgetShowAmountsProvider).valueOrNull;
  if (data == null || showAmounts == null) return;
  final now = ref.read(clockProvider)();
  final summary = ref.watch(
    dashboardSummaryProvider(DateTime(now.year, now.month, now.day)),
  );
  ref
      .read(homeWidgetServiceProvider)
      .push(
        WidgetSnapshot.fromSummary(
          summary,
          code: data.currencyCode,
          showAmounts: showAmounts,
        ),
      );
});
