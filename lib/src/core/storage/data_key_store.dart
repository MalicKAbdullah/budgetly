import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:core_storage/core_storage.dart';

/// Manages the random 256-bit key that encrypts the vault file. Generated once
/// on first launch with a secure RNG and kept in the platform keychain via
/// [ISecureStorage]; never password-derived, never leaves secure storage.
final class DataKeyStore {
  const DataKeyStore(this._secureStorage, {Random? random}) : _random = random;

  static const String storageKey = 'budgetly_data_key';
  static const int keyLengthBytes = 32;

  final ISecureStorage _secureStorage;
  final Random? _random;

  Future<Uint8List> obtainKey() async {
    final existing = await _secureStorage.read(key: storageKey);
    if (existing != null) return base64Decode(existing);

    final rng = _random ?? Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(keyLengthBytes, (_) => rng.nextInt(256)),
    );
    await _secureStorage.write(key: storageKey, value: base64Encode(key));
    return key;
  }
}
