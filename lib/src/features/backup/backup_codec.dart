import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/security/key_derivation.dart';

enum BackupError { invalidFormat, unsupportedVersion, wrongPassphrase }

final class BackupException implements Exception {
  const BackupException(this.error);
  final BackupError error;
  @override
  String toString() => 'BackupException($error)';
}

/// Encrypted, portable `.budgetlybackup` of the whole dataset. The AppData JSON is
/// encrypted with AES-256-GCM under an Argon2id key derived from a *backup
/// passphrase* (independent of the device data key, so it restores on any
/// device).
final class BackupCodec {
  const BackupCodec({
    required IKeyDerivation keyDerivation,
    required CipherService cipher,
  }) : _kdf = keyDerivation,
       _cipher = cipher;

  final IKeyDerivation _kdf;
  final CipherService _cipher;

  static const int formatVersion = 1;
  static const String fileExtension = 'budgetlybackup';
  static const int minPassphraseLength = 8;

  Future<String> encode({
    required AppData data,
    required String passphrase,
    required DateTime createdAt,
  }) async {
    final salt = await _cipher.generateSalt();
    final key = await _kdf.deriveKey(passphrase: passphrase, salt: salt);
    final payload = await _cipher.encrypt(
      plaintext: jsonEncode(data.toJson()),
      keyBytes: key,
      salt: salt,
    );
    key.fillRange(0, key.length, 0);
    return jsonEncode({
      'formatVersion': formatVersion,
      'app': 'budgetly',
      'createdAt': createdAt.toIso8601String(),
      'accountCount': data.accounts.length,
      'txnCount': data.txns.length,
      'salt': base64Encode(salt),
      'nonce': base64Encode(payload.nonce),
      'ciphertext': base64Encode(payload.ciphertext),
    });
  }

  Future<AppData> decode({
    required String raw,
    required String passphrase,
  }) async {
    final Map<String, dynamic> envelope;
    final Uint8List salt;
    final Uint8List nonce;
    final Uint8List ciphertext;
    try {
      envelope = jsonDecode(raw) as Map<String, dynamic>;
      salt = base64Decode(envelope['salt'] as String);
      nonce = base64Decode(envelope['nonce'] as String);
      ciphertext = base64Decode(envelope['ciphertext'] as String);
    } catch (_) {
      throw const BackupException(BackupError.invalidFormat);
    }
    final version = envelope['formatVersion'];
    if (version is! int || version > formatVersion) {
      throw const BackupException(BackupError.unsupportedVersion);
    }

    final key = await _kdf.deriveKey(passphrase: passphrase, salt: salt);
    final String plaintext;
    try {
      plaintext = await _cipher.decrypt(
        payload: EncryptedPayload(
          ciphertext: ciphertext,
          nonce: nonce,
          salt: salt,
        ),
        keyBytes: key,
      );
    } catch (_) {
      throw const BackupException(BackupError.wrongPassphrase);
    } finally {
      key.fillRange(0, key.length, 0);
    }

    try {
      return AppData.fromJson(jsonDecode(plaintext) as Map<String, dynamic>);
    } catch (_) {
      throw const BackupException(BackupError.invalidFormat);
    }
  }
}
