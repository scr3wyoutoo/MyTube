import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'android/app/src/main/kotlin/com/dev/mytube/'
      'AndroidMedia3AudioPlayer.kt',
    ).readAsStringSync();
  });

  test('besitzt zwei langlebige ExoPlayer-Slots', () {
    expect(source, contains('private val slotA = Slot("A")'));
    expect(source, contains('private val slotB = Slot("B")'));
    expect(source, contains('activeSlot = incoming'));
    expect(source, contains('standbySlot = outgoing'));
    expect(source, isNot(contains('outgoing.player.release()')));
  });

  test('überlappt nur vorbereitete Songs mit sechs Sekunden Vorgabe', () {
    expect(source, contains('private var crossfadeDurationMs = 6_000L'));
    expect(
      source,
      contains(
        'if (nextPrepared && current.playWhenReady && remaining <= crossfadeDurationMs)',
      ),
    );
    expect(source, contains('standbySlot.player.play()'));
    expect(source, contains('activeSlot.player.volume'));
    expect(source, contains('standbySlot.player.volume'));
  });

  test(
    'nutzt Netzwerk-Wakelock und delegiert Audiofokus an die App-Session',
    () {
      expect(source, contains('created.setWakeMode(C.WAKE_MODE_NETWORK)'));
      expect(source, contains('created.setHandleAudioBecomingNoisy(false)'));
      expect(source, contains('AUDIO_CONTENT_TYPE_MUSIC'));
    },
  );
}
