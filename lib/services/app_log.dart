import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_log_storage.dart';
import 'app_log_storage_base.dart';
import 'app_log_storage_stub.dart' show MemoryAppLogStorage;

enum AppLogLevel { info, warning, error }

typedef AppLogStorageFactory = Future<AppLogStorage> Function();

class AppLog {
  AppLog._();

  static AppLogService instance = AppLogService();

  @visibleForTesting
  static void replaceForTesting(AppLogService service) {
    instance = service;
  }
}

class AppLogService {
  AppLogService({
    AppLogStorageFactory? storageFactory,
    DateTime Function()? clock,
    String? sessionId,
    this.maxBytes = 2 * 1024 * 1024,
    this.infoFlushDelay = const Duration(milliseconds: 250),
  }) : _storageFactory = storageFactory ?? createAppLogStorage,
       _clock = clock ?? DateTime.now,
       sessionId = sessionId ?? _createSessionId();

  @visibleForTesting
  factory AppLogService.forTesting({
    required AppLogStorage storage,
    DateTime Function()? clock,
    String sessionId = 'test',
    int maxBytes = 2 * 1024 * 1024,
    Duration infoFlushDelay = const Duration(milliseconds: 250),
  }) {
    final service = AppLogService(
      storageFactory: () async => storage,
      clock: clock,
      sessionId: sessionId,
      maxBytes: maxBytes,
      infoFlushDelay: infoFlushDelay,
    );
    service
      .._storage = storage
      .._initialization = Future<void>.value()
      .._appVersion = 'test'
      .._buildNumber = 'test'
      .._enabled = true;
    return service;
  }

  final AppLogStorageFactory _storageFactory;
  final DateTime Function() _clock;
  final String sessionId;
  final int maxBytes;
  final Duration infoFlushDelay;

  final List<String> _pendingLines = <String>[];
  Future<void> _writeChain = Future<void>.value();
  Future<void>? _initialization;
  AppLogStorage? _storage;
  Timer? _flushTimer;
  String _appVersion = 'unknown';
  String _buildNumber = 'unknown';
  bool _enabled = false;

  bool get isInitialized => _storage != null;

  Future<void> initialize() async {
    if (_enabled) {
      return;
    }
    _initialization ??= _initializeStorage();
    await _initialization;
    if (_enabled) {
      return;
    }
    _enabled = true;
    info('diagnostics.logging.initialized', fields: {'maxBytes': maxBytes});
    await flush();
  }

  Future<void> _initializeStorage() async {
    try {
      _storage = await _storageFactory();
    } on Object {
      _storage = MemoryAppLogStorage();
    }
    try {
      final package = await PackageInfo.fromPlatform();
      _appVersion = package.version;
      _buildNumber = package.buildNumber;
    } on Object {
      // Package metadata is useful but must never prevent local logging.
    }
  }

  void info(String event, {Map<String, Object?> fields = const {}}) =>
      record(AppLogLevel.info, event, fields: fields);

  void warning(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => record(
    AppLogLevel.warning,
    event,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  void error(
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) => record(
    AppLogLevel.error,
    event,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  void record(
    AppLogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final values = <String, Object?>{
      'session': sessionId,
      'platform': _platformName,
      'app': _appVersion,
      'build': _buildNumber,
      ...fields,
      if (error != null) 'errorType': error.runtimeType.toString(),
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': _trimStack(stackTrace),
    };
    final buffer = StringBuffer()
      ..write(_clock().toIso8601String())
      ..write(' ')
      ..write(_levelName(level).padRight(5))
      ..write(' ')
      ..write(_sanitizeEvent(event));
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(_sanitizeKey(entry.key))
        ..write('=')
        ..write(_formatValue(value));
    }
    _pendingLines.add('${buffer.toString()}\n');
    if (_pendingLines.length > 1000) {
      _pendingLines.removeRange(0, _pendingLines.length - 1000);
    }
    if (!_enabled) {
      return;
    }
    if (level == AppLogLevel.info) {
      _flushTimer ??= Timer(infoFlushDelay, () {
        _flushTimer = null;
        unawaited(flush());
      });
    } else {
      _flushTimer?.cancel();
      _flushTimer = null;
      unawaited(flush());
    }
  }

  Future<void> flush() async {
    if (!_enabled) {
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    final batch = _pendingLines.join();
    _pendingLines.clear();
    if (batch.isEmpty) {
      return _writeChain;
    }
    final storage = _storage;
    if (storage == null) {
      _pendingLines.insert(0, batch);
      return;
    }
    _writeChain = _writeChain
        .catchError((_) {
          // A failed older write must not permanently poison the queue.
        })
        .then((_) => storage.append(batch, maxBytes: maxBytes));
    try {
      await _writeChain;
    } on Object {
      // Logging is strictly best effort and must not break app workflows.
    }
  }

  Future<String> read() async {
    await initialize();
    await flush();
    return (await _storage!.read()).trimRight();
  }

  Future<void> clear() async {
    await initialize();
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingLines.clear();
    try {
      await _writeChain;
    } on Object {
      // A previous best-effort write must not make clearing impossible.
    }
    await _storage!.clear();
  }

  String opaqueId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _formatValue(Object value) {
    final raw = switch (value) {
      Duration duration => '${duration.inMilliseconds}ms',
      DateTime dateTime => dateTime.toIso8601String(),
      Iterable<Object?> values => values.join(','),
      _ => value.toString(),
    };
    final sanitized = _redact(raw).replaceAll(RegExp(r'[\r\n]+'), r'\n');
    final limited = sanitized.length > 1200
        ? '${sanitized.substring(0, 1200)}…'
        : sanitized;
    if (RegExp(r'^[A-Za-z0-9._:/+@-]+$').hasMatch(limited)) {
      return limited;
    }
    return '"${limited.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  String _redact(String value) {
    var result = value.replaceAllMapped(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      (match) {
        final raw = match.group(0)!;
        final uri = Uri.tryParse(raw);
        if (uri == null || uri.host.isEmpty) {
          return '[URL]';
        }
        return '${uri.scheme}://${uri.host}${uri.path}[query-redacted]';
      },
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(authorization|cookie|set-cookie)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[redacted]',
    );
    return result;
  }

  String _trimStack(StackTrace stackTrace) {
    final lines = stackTrace.toString().split('\n').take(20);
    return lines.join(' | ');
  }

  static String _createSessionId() {
    Random random;
    try {
      random = Random.secure();
    } on UnsupportedError {
      random = Random();
    }
    return List<String>.generate(
      4,
      (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'),
    ).join();
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }
    return defaultTargetPlatform.name;
  }

  String _levelName(AppLogLevel level) => switch (level) {
    AppLogLevel.info => 'INFO',
    AppLogLevel.warning => 'WARN',
    AppLogLevel.error => 'ERROR',
  };

  String _sanitizeEvent(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  String _sanitizeKey(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
}
