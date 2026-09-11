import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/widgets/player_transport_controls.dart';

void main() {
  testWidgets('zeigt Historien-Zurück und Vorwärts/Queue-Weiter ohne Stop', (
    tester,
  ) async {
    var previousCalls = 0;
    var playCalls = 0;
    var nextCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: PlayerTransportControls(
                playing: false,
                previousEnabled: true,
                nextEnabled: true,
                onPrevious: () => previousCalls++,
                onTogglePlayback: () => playCalls++,
                onNext: () => nextCalls++,
                showPictureInPicture: true,
                onPictureInPicture: () {},
                fullscreen: false,
                onToggleFullscreen: () {},
                onOpenSettings: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.fast_rewind), findsNothing);
    expect(find.byIcon(Icons.fast_forward), findsNothing);
    expect(find.byIcon(Icons.stop), findsNothing);

    await tester.tap(find.byKey(const Key('player-history-back-button')));
    await tester.tap(find.byKey(const Key('player-play-pause-button')));
    await tester.tap(find.byKey(const Key('player-forward-button')));
    expect(previousCalls, 1);
    expect(playCalls, 1);
    expect(nextCalls, 1);

    final controls = tester.getRect(
      find.byKey(const Key('player-transport-controls')),
    );
    final pictureInPicture = tester.getRect(
      find.byKey(const Key('picture-in-picture-button')),
    );
    final fullscreen = tester.getRect(
      find.byKey(const Key('fullscreen-button')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('player-settings-button')),
    );

    expect(fullscreen.left, pictureInPicture.right);
    expect(settings.left, fullscreen.right);
    expect(controls.right - settings.right, 4);
  });

  testWidgets('deaktiviert Richtungen ohne Zielmedium', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerTransportControls(
            playing: true,
            previousEnabled: false,
            nextEnabled: false,
            onPrevious: () {},
            onTogglePlayback: () {},
            onNext: () {},
            showPictureInPicture: false,
            onPictureInPicture: null,
            fullscreen: true,
            onToggleFullscreen: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('player-history-back-button')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('player-forward-button')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('picture-in-picture-button')), findsNothing);
    expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
  });
}
