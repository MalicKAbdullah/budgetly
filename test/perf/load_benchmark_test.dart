import 'dart:isolate';
import 'dart:typed_data';

import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/storage/budgetly_store.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench.dart';
import 'perf_data.dart';

/// Vault decode and encode for 5,000 transactions: on the calling (UI)
/// isolate versus on a background isolate. "Longest UI stall" is what a
/// frame or the biometric platform reply would have waited.
void main() {
  test('vault load and save, 5,000 transactions', () async {
    const cipher = CipherService();
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final data = perfData(today: DateTime.now());
    final bytes = await BudgetlyStore.encode(cipher, data, key);

    Future<void> decodeInline() => BudgetlyStore.decode(cipher, bytes, key);
    Future<void> decodeIsolate() => _decodeOnIsolate(cipher, bytes, key);
    Future<void> encodeInline() => BudgetlyStore.encode(cipher, data, key);
    Future<void> encodeIsolate() => _encodeOnIsolate(cipher, data, key);

    final rows = {
      'decode, UI isolate: wall': await medianMs(decodeInline),
      'decode, UI isolate: longest UI stall': await longestStallMs(
        decodeInline,
      ),
      'decode, background isolate: wall': await medianMs(decodeIsolate),
      'decode, background isolate: longest UI stall': await longestStallMs(
        decodeIsolate,
      ),
      'encode, UI isolate: wall': await medianMs(encodeInline),
      'encode, UI isolate: longest UI stall': await longestStallMs(
        encodeInline,
      ),
      'encode, background isolate: wall': await medianMs(encodeIsolate),
      'encode, background isolate: longest UI stall': await longestStallMs(
        encodeIsolate,
      ),
    };
    report('vault, ${bytes.length} bytes, ${data.txns.length} txns', rows);

    expect(
      rows['decode, background isolate: longest UI stall']!,
      lessThan(rows['decode, UI isolate: longest UI stall']!),
    );
  });
}

// Built outside the test body so each isolate closure captures only
// sendable values.
Future<void> _decodeOnIsolate(
  CipherService cipher,
  Uint8List bytes,
  Uint8List key,
) => Isolate.run(() => BudgetlyStore.decode(cipher, bytes, key));

Future<void> _encodeOnIsolate(
  CipherService cipher,
  AppData data,
  Uint8List key,
) => Isolate.run(() => BudgetlyStore.encode(cipher, data, key));
