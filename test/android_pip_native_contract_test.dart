import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manueller Android-PiP-Eintritt erhält Auto-Enter', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/flutter_browser_app/'
      'MainActivity.kt',
    ).readAsStringSync();
    final enterStart = source.indexOf('"enter" -> {');
    final handlerEnd = source.indexOf(
      'else -> result.notImplemented()',
      enterStart,
    );
    final enterBlock = source.substring(enterStart, handlerEnd);

    expect(
      enterBlock,
      contains('createPictureInPictureParams(autoEnter = autoEnterEnabled)'),
    );
    expect(
      enterBlock,
      isNot(contains('createPictureInPictureParams(autoEnter = false)')),
    );
  });

  test('Android stellt PiP-Parameter nach Rückkehr in die App wieder her', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/flutter_browser_app/'
      'MainActivity.kt',
    ).readAsStringSync();
    final resumeStart = source.indexOf('override fun onPostResume()');
    final stopStart = source.indexOf('override fun onStop()', resumeStart);
    final resumeBlock = source.substring(resumeStart, stopStart);

    expect(resumeBlock, contains('updatePictureInPictureParams()'));
  });

  test('Media3 meldet Wiedergabeabsicht unabhängig vom Bufferstatus', () {
    final source = File(
      'android/app/src/main/kotlin/com/example/flutter_browser_app/'
      'AndroidMedia3VideoPlayer.kt',
    ).readAsStringSync();

    expect(source, contains('override fun onPlayWhenReadyChanged'));
    expect(source, contains('current.playWhenReady &&'));
    expect(source, contains('"playbackRequested" to playbackRequested'));
  });
}
