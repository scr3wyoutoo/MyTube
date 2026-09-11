import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_browser_app/main.dart';
import 'package:flutter_browser_app/services/profile_controller.dart';
import 'package:flutter_browser_app/theme/mytube_theme.dart';
import 'package:flutter_browser_app/widgets/mytube_startup_splash.dart';

void main() {
  test('MyTube-Theme nutzt die verbindliche Branding-Palette', () {
    final theme = buildMyTubeTheme();

    expect(theme.colorScheme.primary, MyTubeColors.coral);
    expect(theme.colorScheme.secondary, MyTubeColors.turquoise);
    expect(theme.colorScheme.surface, MyTubeColors.cream);
    expect(theme.colorScheme.onSurface, MyTubeColors.navy);
    expect(theme.scaffoldBackgroundColor, MyTubeColors.cream);
    expect(theme.cardTheme.color, MyTubeColors.creamLight);
    expect(theme.navigationBarTheme.backgroundColor, MyTubeColors.creamDark);
  });

  testWidgets('Android-Branding-Splash blendet aus und gibt App frei', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMyTubeTheme(),
        home: const MyTubeStartupSplash(
          minimumDuration: Duration(milliseconds: 100),
          fadeDuration: Duration(milliseconds: 50),
          child: Scaffold(body: Text('App bereit')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mytube-startup-splash')), findsOneWidget);
    expect(find.text('App bereit'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/branding/mytube_splash_source.png')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 101));
    expect(find.byKey(const ValueKey('mytube-startup-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 51));
    expect(find.byKey(const ValueKey('mytube-startup-splash')), findsNothing);
    expect(find.text('App bereit'), findsOneWidget);
  });

  testWidgets('Android zeichnet das Artwork vor der Initialisierung', (
    tester,
  ) async {
    final profileCompleter = Completer<ProfileController>();
    var mediaInitializations = 0;
    var profileLoads = 0;

    await tester.pumpWidget(
      MyTubeAndroidBootstrap(
        initializeMedia: () => mediaInitializations++,
        loadProfile: () {
          profileLoads++;
          return profileCompleter.future;
        },
      ),
    );

    expect(find.byKey(const ValueKey('mytube-splash-artwork')), findsOneWidget);
    expect(mediaInitializations, 1);
    expect(profileLoads, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('mytube-splash-artwork')), findsOneWidget);

    profileCompleter.complete(ProfileController.inMemory());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('mytube-startup-splash')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump(const Duration(milliseconds: 251));
    expect(find.byKey(const ValueKey('mytube-startup-splash')), findsNothing);
  });
}
