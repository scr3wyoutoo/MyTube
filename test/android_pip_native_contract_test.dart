import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manueller Android-PiP-Eintritt erhält Auto-Enter', () {
    final source = File(
      'android/app/src/main/kotlin/com/dev/mytube/'
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
      'android/app/src/main/kotlin/com/dev/mytube/'
      'MainActivity.kt',
    ).readAsStringSync();
    final resumeStart = source.indexOf('override fun onPostResume()');
    final stopStart = source.indexOf('override fun onStop()', resumeStart);
    final resumeBlock = source.substring(resumeStart, stopStart);

    expect(resumeBlock, contains('updatePictureInPictureParams()'));
  });

  test('Media3 meldet Wiedergabeabsicht unabhängig vom Bufferstatus', () {
    final source = File(
      'android/app/src/main/kotlin/com/dev/mytube/'
      'AndroidMedia3VideoPlayer.kt',
    ).readAsStringSync();

    expect(source, contains('override fun onPlayWhenReadyChanged'));
    expect(source, contains('current.playWhenReady &&'));
    expect(source, contains('"playbackRequested" to playbackRequested'));
  });

  test('Media3 hält das Display nur bei aktiver Videoabsicht wach', () {
    final source = File(
      'android/app/src/main/kotlin/com/dev/mytube/'
      'AndroidMedia3VideoPlayer.kt',
    ).readAsStringSync();

    expect(source, contains('private fun updateKeepScreenOn'));
    expect(source, contains('attachedTextureView?.keepScreenOn ='));
    expect(source, contains('current.playWhenReady &&'));
    expect(source, contains('current.playbackState != Player.STATE_ENDED &&'));
    expect(source, contains('current.mediaItemCount > 0 &&'));
    expect(source, contains('current.playerError == null'));
  });

  test('Media3 löst den Display-Wakelock beim Ablösen und Freigeben', () {
    final source = File(
      'android/app/src/main/kotlin/com/dev/mytube/'
      'AndroidMedia3VideoPlayer.kt',
    ).readAsStringSync();

    final detachStart = source.indexOf('fun detachTextureView');
    final playbackCallbackStart = source.indexOf(
      'override fun onPlaybackStateChanged',
      detachStart,
    );
    final detachBlock = source.substring(detachStart, playbackCallbackStart);
    final releaseStart = source.indexOf('fun release()');
    final stringMapStart = source.indexOf(
      'private fun stringMap',
      releaseStart,
    );
    final releaseBlock = source.substring(releaseStart, stringMapStart);

    expect(detachBlock, contains('view.keepScreenOn = false'));
    expect(releaseBlock, contains('view.keepScreenOn = false'));
  });
}
