import 'dart:convert';

import 'app_log_storage_base.dart';

Future<AppLogStorage> createAppLogStorage() async => MemoryAppLogStorage();

class MemoryAppLogStorage implements AppLogStorage {
  String _value = '';

  @override
  Future<void> append(String value, {required int maxBytes}) async {
    _value += value;
    if (utf8.encode(_value).length <= maxBytes) {
      return;
    }
    _value = retainNewestLogText(_value, maxBytes: maxBytes);
  }

  @override
  Future<void> clear() async => _value = '';

  @override
  Future<String> read() async => _value;
}

String retainNewestLogText(String value, {required int maxBytes}) {
  final targetBytes = (maxBytes * 0.75).floor();
  final lines = const LineSplitter().convert(value);
  final retained = <String>[];
  var retainedBytes = 0;
  for (var index = lines.length - 1; index >= 0; index--) {
    final line = lines[index];
    final lineBytes = utf8.encode('$line\n').length;
    if (retained.isNotEmpty && retainedBytes + lineBytes > targetBytes) {
      break;
    }
    retained.add(line);
    retainedBytes += lineBytes;
  }
  return '${retained.reversed.join('\n')}\n';
}
