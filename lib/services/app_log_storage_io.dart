import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_log_storage_base.dart';
import 'app_log_storage_stub.dart' show retainNewestLogText;

Future<AppLogStorage> createAppLogStorage() async {
  final directory = await getApplicationSupportDirectory();
  return FileAppLogStorage(
    File('${directory.path}${Platform.pathSeparator}mytube.log'),
  );
}

class FileAppLogStorage implements AppLogStorage {
  FileAppLogStorage(this.file);

  final File file;

  Future<void> _ensureParent() => file.parent.create(recursive: true);

  @override
  Future<void> append(String value, {required int maxBytes}) async {
    await _ensureParent();
    await file.writeAsString(value, mode: FileMode.append, flush: false);
    if (await file.length() <= maxBytes) {
      return;
    }
    final current = await file.readAsString();
    final retained = retainNewestLogText(current, maxBytes: maxBytes);
    await file.writeAsString(retained, mode: FileMode.write, flush: true);
  }

  @override
  Future<void> clear() async {
    await _ensureParent();
    await file.writeAsString('', mode: FileMode.write, flush: true);
  }

  @override
  Future<String> read() async {
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }
}
