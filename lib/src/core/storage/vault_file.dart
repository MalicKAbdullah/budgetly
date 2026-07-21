import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// File abstraction so the repository is unit-testable with an in-memory fake.
abstract interface class IVaultFile {
  Future<Uint8List?> read();
  Future<void> write(Uint8List bytes);
}

/// Single encrypted vault file in the app documents directory. Writes go to a
/// temp file then rename, so an interrupted write can't corrupt the vault.
final class LocalVaultFile implements IVaultFile {
  LocalVaultFile({this.fileName = 'budgetly.vault'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<Uint8List?> read() async {
    final file = await _file();
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
