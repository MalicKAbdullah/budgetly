import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/storage/data_key_store.dart';
import 'package:tally/src/core/storage/vault_file.dart';

/// Persistence: JSON → AES-256-GCM → single vault file. Load-decrypt on start,
/// encrypt-write on every mutation.
final class TallyStore {
  const TallyStore({
    required CipherService cipher,
    required DataKeyStore keyStore,
    required IVaultFile file,
  }) : _cipher = cipher,
       _keyStore = keyStore,
       _file = file;

  final CipherService _cipher;
  final DataKeyStore _keyStore;
  final IVaultFile _file;

  Future<AppData> load() async {
    final bytes = await _file.read();
    if (bytes == null) return const AppData();
    final key = await _keyStore.obtainKey();
    final plaintext = await _cipher.decrypt(
      payload: EncryptedPayload.fromBytes(bytes),
      keyBytes: key,
    );
    return AppData.fromJson(jsonDecode(plaintext) as Map<String, dynamic>);
  }

  Future<void> save(AppData data) async {
    final key = await _keyStore.obtainKey();
    final payload = await _cipher.encrypt(
      plaintext: jsonEncode(data.toJson()),
      keyBytes: key,
      salt: await _cipher.generateSalt(),
    );
    await _file.write(payload.toBytes());
  }
}
