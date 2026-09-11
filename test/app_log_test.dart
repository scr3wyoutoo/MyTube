import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/services/app_log.dart';
import 'package:flutter_browser_app/services/app_log_storage_stub.dart';

void main() {
  test(
    'schreibt strukturierte Einträge und entfernt sensible URL-Daten',
    () async {
      final storage = MemoryAppLogStorage();
      final logger = AppLogService(
        storageFactory: () async => storage,
        sessionId: 'session-test',
        clock: () => DateTime.utc(2026, 9, 9, 18),
        infoFlushDelay: Duration.zero,
      );

      await logger.initialize();
      logger.info(
        'playback.test',
        fields: {
          'url': 'https://googlevideo.com/videoplayback?token=secret',
          'cookie': 'Cookie=session-secret',
          'duration': const Duration(milliseconds: 321),
        },
      );
      logger.error(
        'playback.failed',
        error: StateError('kaputt'),
        stackTrace: StackTrace.current,
      );
      await logger.flush();

      final contents = await logger.read();
      expect(contents, contains('INFO  playback.test'));
      expect(contents, contains('ERROR playback.failed'));
      expect(contents, contains('session=session-test'));
      expect(contents, contains('duration=321ms'));
      expect(
        contents,
        contains('https://googlevideo.com/videoplayback[query-redacted]'),
      );
      expect(contents, contains('Cookie=[redacted]'));
      expect(contents, isNot(contains('token=secret')));
      expect(contents, isNot(contains('session-secret')));
    },
  );

  test(
    'begrenzt das Log rollierend und behält die neuesten Einträge',
    () async {
      final storage = MemoryAppLogStorage();
      final logger = AppLogService(
        storageFactory: () async => storage,
        sessionId: 'roll-test',
        maxBytes: 1600,
        infoFlushDelay: Duration.zero,
      );
      await logger.initialize();

      for (var index = 0; index < 100; index++) {
        logger.info(
          'rolling.entry',
          fields: {'index': index, 'payload': 'x' * 80},
        );
        await logger.flush();
      }

      final contents = await logger.read();
      expect(contents.length, lessThanOrEqualTo(1600));
      expect(contents, contains('index=99'));
      expect(contents, isNot(contains('index=0 ')));
    },
  );

  test('leert die Logdatei vollständig', () async {
    final storage = MemoryAppLogStorage();
    final logger = AppLogService(
      storageFactory: () async => storage,
      sessionId: 'clear-test',
      infoFlushDelay: Duration.zero,
    );
    await logger.initialize();
    logger.warning('test.before_clear');
    await logger.flush();
    expect(await logger.read(), isNotEmpty);

    await logger.clear();

    expect(await logger.read(), isEmpty);
  });

  test('bildet Suchbegriffe stabil auf nicht lesbare IDs ab', () {
    final logger = AppLogService(sessionId: 'hash-test');

    expect(logger.opaqueId('arte'), logger.opaqueId('arte'));
    expect(logger.opaqueId('arte'), isNot(logger.opaqueId('music')));
    expect(logger.opaqueId('arte'), isNot(contains('arte')));
  });
}
