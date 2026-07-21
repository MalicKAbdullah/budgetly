import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_backup/core_backup.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_storage/core_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/data/app_data_notifier.dart';
import 'package:tally/src/core/security/key_derivation.dart';
import 'package:tally/src/core/storage/data_key_store.dart';
import 'package:tally/src/core/storage/tally_store.dart';
import 'package:tally/src/core/storage/vault_file.dart';
import 'package:tally/src/features/backup/backup_codec.dart';

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

final tallyStoreProvider = Provider<TallyStore>(
  (ref) => TallyStore(
    cipher: ref.watch(cipherServiceProvider),
    keyStore: ref.watch(dataKeyStoreProvider),
    file: ref.watch(vaultFileProvider),
  ),
);

/// The single source of truth for all app data.
final appDataProvider = AsyncNotifierProvider<AppDataNotifier, AppData>(
  AppDataNotifier.new,
);

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
    keyPrefix: 'tally',
    fileLabel: 'Tally',
    fileExtension: BackupCodec.fileExtension,
    now: () => ref.read(clockProvider)(),
  ),
);

/// Produces the encrypted `.tallybackup` bytes for the current dataset.
final tallyBackupProducerProvider = Provider<BackupProducer>((ref) {
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
