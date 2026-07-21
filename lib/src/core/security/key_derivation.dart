import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

/// Abstraction over passphrase key derivation so tests inject a fast fake
/// instead of running Argon2id.
abstract interface class IKeyDerivation {
  Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
  });
}

/// Production Argon2id derivation (core_crypto, OWASP params, background
/// isolate). Used for portable, passphrase-encrypted backups.
final class Argon2KeyDerivation implements IKeyDerivation {
  const Argon2KeyDerivation(this._service);

  final KeyDerivationService _service;

  @override
  Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
  }) => _service.deriveKey(masterPassword: passphrase, salt: salt);
}
