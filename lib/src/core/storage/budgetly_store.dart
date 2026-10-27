import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/storage/data_key_store.dart';
import 'package:budgetly/src/core/storage/vault_file.dart';

/// Runs a piece of vault work and returns its result: [Isolate.run] in the
/// app. Widget tests run it inline, because their fake clock cannot wait on
/// another isolate.
typedef VaultWorker = Future<R> Function<R>(FutureOr<R> Function() work);

/// Persistence: JSON → AES-256-GCM → single vault file. Load-decrypt on start,
/// encrypt-write on every mutation.
///
/// Decrypt + parse and serialize + encrypt cover the whole dataset, so both
/// run on the [VaultWorker], a background isolate: on launch that work
/// overlaps the biometric prompt without holding up the UI isolate that has
/// to answer it.
final class BudgetlyStore {
  BudgetlyStore({
    required CipherService cipher,
    required DataKeyStore keyStore,
    required IVaultFile file,
    required VaultWorker worker,
  }) : _cipher = cipher,
       _keyStore = keyStore,
       _file = file,
       _worker = worker;

  final CipherService _cipher;
  final DataKeyStore _keyStore;
  final IVaultFile _file;
  final VaultWorker _worker;

  /// The latest queued write. Saves encrypt concurrently but reach the file
  /// in call order, so an older snapshot can never land after a newer one.
  Future<void> _lastWrite = Future.value();

  Future<AppData> load() async {
    final bytes = await _file.read();
    if (bytes == null) return const AppData();
    final key = await _keyStore.obtainKey();
    final watch = Stopwatch()..start();
    final data = await _decodeOn(_worker, _cipher, bytes, key);
    _log(
      'vault decrypt + parse ${watch.elapsedMilliseconds} ms '
      '(${bytes.length} bytes, ${data.txns.length} txns)',
    );
    return data;
  }

  Future<void> save(AppData data) async {
    final key = await _keyStore.obtainKey();
    final watch = Stopwatch()..start();
    final encoded = _encodeOn(_worker, _cipher, data, key);
    final write = _lastWrite.then((_) async {
      final bytes = await encoded;
      _log('vault serialize + encrypt ${watch.elapsedMilliseconds} ms');
      await _file.write(bytes);
    });
    // The queue only orders writes; a failed one reports to its own caller
    // and must not block the saves behind it.
    _lastWrite = write.then<void>((_) {}, onError: (_) {});
    return write;
  }

  // A closure sent to an isolate carries every variable of the scope it is
  // created in, so it is built here, where that scope holds only sendable
  // values.
  static Future<AppData> _decodeOn(
    VaultWorker worker,
    CipherService cipher,
    Uint8List bytes,
    Uint8List key,
  ) => worker(() => decode(cipher, bytes, key));

  static Future<Uint8List> _encodeOn(
    VaultWorker worker,
    CipherService cipher,
    AppData data,
    Uint8List key,
  ) => worker(() => encode(cipher, data, key));

  /// The vault file's bytes back to the dataset.
  static Future<AppData> decode(
    CipherService cipher,
    Uint8List bytes,
    Uint8List key,
  ) async {
    final plaintext = await cipher.decrypt(
      payload: EncryptedPayload.fromBytes(bytes),
      keyBytes: key,
    );
    return AppData.fromJson(jsonDecode(plaintext) as Map<String, dynamic>);
  }

  /// The dataset as vault file bytes.
  static Future<Uint8List> encode(
    CipherService cipher,
    AppData data,
    Uint8List key,
  ) async {
    final payload = await cipher.encrypt(
      plaintext: jsonEncode(data.toJson()),
      keyBytes: key,
      salt: await cipher.generateSalt(),
    );
    return payload.toBytes();
  }

  static void _log(String message) {
    if (!kReleaseMode) developer.log(message, name: 'budgetly.perf');
  }
}
