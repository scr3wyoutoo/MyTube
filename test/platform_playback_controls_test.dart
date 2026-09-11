import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/services/android_picture_in_picture.dart';
import 'package:flutter_browser_app/services/android_media3_audio_playback.dart';
import 'package:flutter_browser_app/services/ios_native_audio_playback.dart';
import 'package:flutter_browser_app/services/ios_picture_in_picture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('übergibt Android-Songs an zwei native Media3-Audioslots', () async {
    AndroidMedia3AudioPlayback.debugSupportedPlatformOverride = true;
    addTearDown(
      () => AndroidMedia3AudioPlayback.debugSupportedPlatformOverride = null,
    );

    const channel = MethodChannel(
      'flutter_browser_app/android_media3_audio_playback',
    );
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await AndroidMedia3AudioPlayback.instance.attach(
      onStateChanged: (_) {},
      onCompleted: () {},
      onAdvanced: () {},
      onFailed: (_) {},
    );
    final opened = await AndroidMedia3AudioPlayback.instance.open(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/current'),
      headers: const {'User-Agent': 'MyTube-Test'},
      isHls: false,
      volume: 0.8,
      position: const Duration(seconds: 4),
      playing: true,
      expectedDuration: const Duration(minutes: 2, seconds: 33),
    );
    final prepared = await AndroidMedia3AudioPlayback.instance.prepareNext(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/next'),
      headers: const {'User-Agent': 'MyTube-Test'},
      isHls: false,
      expectedDuration: const Duration(minutes: 3),
    );
    await AndroidMedia3AudioPlayback.instance.seek(const Duration(seconds: 12));
    await AndroidMedia3AudioPlayback.instance.setVolume(0.4);
    await AndroidMedia3AudioPlayback.instance.pause();
    await AndroidMedia3AudioPlayback.instance.play();
    await AndroidMedia3AudioPlayback.instance.clearNext();
    await AndroidMedia3AudioPlayback.instance.stop();

    expect(opened, isTrue);
    expect(prepared, isTrue);
    expect(
      calls.map((call) => call.method),
      containsAll(<String>[
        'open',
        'prepareNext',
        'seek',
        'setVolume',
        'pause',
        'play',
        'clearNext',
        'stop',
      ]),
    );
    final openArguments =
        calls.firstWhere((call) => call.method == 'open').arguments
            as Map<Object?, Object?>;
    expect(openArguments['positionMilliseconds'], 4000);
    expect(openArguments['crossfadeMilliseconds'], 6000);
    expect(openArguments['expectedDurationMilliseconds'], 153000);
    expect(openArguments['isHls'], isFalse);

    await AndroidMedia3AudioPlayback.instance.detach();
  });

  test('übergibt zwei native iOS-Audioslots und Queue-Steuerung', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel(
      'flutter_browser_app/ios_native_audio_playback',
    );
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await IosNativeAudioPlayback.instance.attach(
      onStateChanged: (_) {},
      onCompleted: () {},
      onAdvanced: () {},
      onPreviousRequested: () {},
      onNextRequested: () {},
      onAudioRoutePaused: () {},
      onFailed: (_) {},
    );
    final opened = await IosNativeAudioPlayback.instance.open(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/current'),
      title: 'Aktuell',
      artist: 'Künstler',
      thumbnailUrl: 'https://example.com/current.jpg',
      volume: 0.8,
      position: const Duration(seconds: 4),
      playing: true,
      hasPrevious: true,
      hasNext: true,
      expectedDuration: const Duration(minutes: 2, seconds: 33),
    );
    final prepared = await IosNativeAudioPlayback.instance.prepareNext(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/next'),
      title: 'Danach',
      artist: 'Künstler',
      thumbnailUrl: 'https://example.com/next.jpg',
      hasNext: false,
      expectedDuration: const Duration(minutes: 3),
    );
    await IosNativeAudioPlayback.instance.updateNavigation(
      hasPrevious: true,
      hasNext: false,
    );
    await IosNativeAudioPlayback.instance.seek(const Duration(seconds: 12));
    await IosNativeAudioPlayback.instance.setVolume(0.4);
    await IosNativeAudioPlayback.instance.pause();
    await IosNativeAudioPlayback.instance.play();
    await IosNativeAudioPlayback.instance.clearNext();
    await IosNativeAudioPlayback.instance.stop();

    expect(opened, isTrue);
    expect(prepared, isTrue);
    expect(
      calls.map((call) => call.method),
      containsAll(<String>[
        'open',
        'prepareNext',
        'updateNavigation',
        'seek',
        'setVolume',
        'pause',
        'play',
        'clearNext',
        'stop',
      ]),
    );
    final openArguments =
        calls.firstWhere((call) => call.method == 'open').arguments
            as Map<Object?, Object?>;
    expect(openArguments['positionMilliseconds'], 4000);
    expect(openArguments['crossfadeMilliseconds'], 6000);
    expect(openArguments['hasPrevious'], isTrue);
    expect(openArguments['hasNext'], isTrue);
    expect(openArguments['expectedDurationMilliseconds'], 153000);
    expect(openArguments['remoteControlsEnabled'], isTrue);

    await IosNativeAudioPlayback.instance.detach();
  });

  test('übergibt iOS-PiP Stream, Metadaten und Wiedergabeposition', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel('flutter_browser_app/ios_picture_in_picture');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'readDebugState') {
        return <String, Object?>{
          'itemStatus': 'readyToPlay',
          'pipPossible': true,
        };
      }
      if (call.method == 'testHlsReadiness') {
        return <String, Object?>{
          'outcome': 'ready',
          'itemStatus': 'readyToPlay',
          'pipPossible': true,
        };
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await IosPictureInPicture.instance.attach(
      onStarted: () {},
      onStopped: (_, _, _) {},
      onFailed: (_) {},
    );
    final configured = await IosPictureInPicture.instance.openMainPlayer(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/1'),
      title: 'Testtitel',
      artist: 'Testkünstler',
      thumbnailUrl: 'https://example.com/cover.jpg',
      playbackVolume: 0.8,
      position: const Duration(seconds: 12),
      playing: true,
      autoEnterEnabled: true,
      pictureInPictureEnabled: true,
      continuesAudioInBackground: false,
      isLive: false,
    );
    await IosPictureInPicture.instance.setAutoEnterEnabled(false);
    await IosPictureInPicture.instance.seek(const Duration(seconds: 21));
    final autoEnterArmed = await IosPictureInPicture.instance.armAutoEnter(
      position: const Duration(seconds: 17),
      playing: true,
    );
    await IosPictureInPicture.instance.cancelAutoEnter();
    final started = await IosPictureInPicture.instance.start(
      position: const Duration(seconds: 42),
      playing: true,
      debugRequestId: 7,
    );
    final debugState = await IosPictureInPicture.instance.readDebugState(
      requestId: 7,
      checkpoint: 'afterStartRequest',
      trigger: 'manualButton',
    );
    final hlsTest = await IosPictureInPicture.instance.testHlsReadiness(
      streamUrl: Uri.parse('http://127.0.0.1:1234/manifest/3'),
      timeout: const Duration(seconds: 9),
    );
    final nextConfigured = await IosPictureInPicture.instance.configureNext(
      streamUrl: Uri.parse('http://127.0.0.1:1234/stream/2'),
      title: 'NÃ¤chster Titel',
      artist: 'TestkÃ¼nstler',
      thumbnailUrl: 'https://example.com/next-cover.jpg',
      hasNextItem: false,
      isLive: true,
    );
    await IosPictureInPicture.instance.pause();
    await IosPictureInPicture.instance.play();
    await IosPictureInPicture.instance.clearNext();

    expect(configured, isTrue);
    expect(autoEnterArmed, isTrue);
    expect(started, isTrue);
    expect(nextConfigured, isTrue);
    expect(
      calls.map((call) => call.method),
      containsAll([
        'openMainPlayer',
        'seek',
        'armAutoEnter',
        'cancelAutoEnter',
        'start',
        'configureNext',
        'pause',
        'play',
        'clearNext',
      ]),
    );
    final startArguments =
        calls.firstWhere((call) => call.method == 'start').arguments
            as Map<Object?, Object?>;
    expect(startArguments['positionMilliseconds'], 42000);
    expect(startArguments['playing'], isTrue);
    expect(startArguments['seekToPosition'], isTrue);
    expect(startArguments['debugRequestId'], 7);
    expect(startArguments['notifyFailure'], isTrue);
    expect(startArguments['readinessTimeoutMilliseconds'], 15000);
    final armAutoEnterArguments =
        calls.firstWhere((call) => call.method == 'armAutoEnter').arguments
            as Map<Object?, Object?>;
    expect(armAutoEnterArguments['positionMilliseconds'], 17000);
    expect(armAutoEnterArguments['playing'], isTrue);
    expect(armAutoEnterArguments['seekToPosition'], isTrue);
    final configureArguments =
        calls.firstWhere((call) => call.method == 'openMainPlayer').arguments
            as Map<Object?, Object?>;
    expect(configureArguments['playbackVolume'], 0.8);
    expect(configureArguments['positionMilliseconds'], 12000);
    expect(configureArguments['playing'], isTrue);
    expect(configureArguments['autoEnterEnabled'], isTrue);
    expect(configureArguments['pictureInPictureEnabled'], isTrue);
    expect(configureArguments['continuesAudioInBackground'], isFalse);
    expect(configureArguments['isLive'], isFalse);
    final seekArguments =
        calls.firstWhere((call) => call.method == 'seek').arguments
            as Map<Object?, Object?>;
    expect(seekArguments['positionMilliseconds'], 21000);
    expect(debugState['itemStatus'], 'readyToPlay');
    expect(debugState['pipPossible'], isTrue);
    expect(hlsTest['outcome'], 'ready');
    expect(hlsTest['pipPossible'], isTrue);
    final debugArguments =
        calls.firstWhere((call) => call.method == 'readDebugState').arguments
            as Map<Object?, Object?>;
    expect(debugArguments['requestId'], 7);
    expect(debugArguments['checkpoint'], 'afterStartRequest');
    expect(debugArguments['trigger'], 'manualButton');
    final hlsTestArguments =
        calls.firstWhere((call) => call.method == 'testHlsReadiness').arguments
            as Map<Object?, Object?>;
    expect(hlsTestArguments['streamUrl'], 'http://127.0.0.1:1234/manifest/3');
    expect(hlsTestArguments['timeoutMilliseconds'], 9000);
    final configureNextArguments =
        calls.firstWhere((call) => call.method == 'configureNext').arguments
            as Map<Object?, Object?>;
    expect(configureNextArguments['isLive'], isTrue);
    final autoEnterArguments =
        calls
                .firstWhere((call) => call.method == 'setAutoEnterEnabled')
                .arguments
            as Map<Object?, Object?>;
    expect(autoEnterArguments['enabled'], isFalse);

    await IosPictureInPicture.instance.detach();
  });

  test('iOS-PiP kann Live-HLS ohne Positionssprung starten', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel('flutter_browser_app/ios_picture_in_picture');
    MethodCall? startCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'start') {
        startCall = call;
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final started = await IosPictureInPicture.instance.start(
      position: const Duration(seconds: 42),
      playing: true,
      seekToPosition: false,
      notifyFailure: false,
      readinessTimeout: const Duration(seconds: 5),
    );

    expect(started, isTrue);
    final arguments = startCall?.arguments as Map<Object?, Object?>;
    expect(arguments['positionMilliseconds'], 42000);
    expect(arguments['seekToPosition'], isFalse);
    expect(arguments['notifyFailure'], isFalse);
    expect(arguments['readinessTimeoutMilliseconds'], 5000);
  });

  test(
    'kann Android-PiP explizit über die Player-Schaltfläche starten',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const channel = MethodChannel('flutter_browser_app/picture_in_picture');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'enter';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await AndroidPictureInPicture.instance.attach(
        onTogglePlayback: () async {},
        onModeChanged: (_, _) {},
        playing: true,
        videoWidth: 16,
        videoHeight: 9,
      );
      final started = await AndroidPictureInPicture.instance.enter();

      expect(started, isTrue);
      expect(calls.map((call) => call.method), ['configure', 'enter']);
      final configureArguments = calls.first.arguments as Map<Object?, Object?>;
      expect(configureArguments['autoEnterEnabled'], isTrue);

      await AndroidPictureInPicture.instance.detach();
    },
  );

  test('deaktiviert Android-Auto-PiP für Audioinhalte', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel('flutter_browser_app/picture_in_picture');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await AndroidPictureInPicture.instance.attach(
      onTogglePlayback: () async {},
      onModeChanged: (_, _) {},
      playing: true,
      videoWidth: 16,
      videoHeight: 9,
      enabled: false,
    );

    final arguments = calls.first.arguments as Map<Object?, Object?>;
    expect(arguments['enabled'], isFalse);
    expect(arguments['autoEnterEnabled'], isFalse);
    await AndroidPictureInPicture.instance.detach();
    debugDefaultTargetPlatformOverride = null;
  });

  test('deaktiviert Android-Auto-PiP für ein pausiertes Video', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    const channel = MethodChannel('flutter_browser_app/picture_in_picture');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await AndroidPictureInPicture.instance.attach(
      onTogglePlayback: () async {},
      onModeChanged: (_, _) {},
      playing: false,
      videoWidth: 16,
      videoHeight: 9,
      enabled: true,
    );

    final arguments = calls.first.arguments as Map<Object?, Object?>;
    expect(arguments['enabled'], isTrue);
    expect(arguments['playing'], isFalse);
    expect(arguments['autoEnterEnabled'], isFalse);
    await AndroidPictureInPicture.instance.detach();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android-Auto-PiP kann bei angeforderter Wiedergabe während Buffering aktiv bleiben',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const channel = MethodChannel('flutter_browser_app/picture_in_picture');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await AndroidPictureInPicture.instance.update(
        enabled: true,
        playing: false,
        videoWidth: 16,
        videoHeight: 9,
        autoEnterEnabled: true,
      );

      final arguments = calls.single.arguments as Map<Object?, Object?>;
      expect(arguments['playing'], isFalse);
      expect(arguments['autoEnterEnabled'], isTrue);
    },
  );
}
