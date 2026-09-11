import 'package:flutter/material.dart';

/// Zentrale Farbpalette des MyTube-App-Icons und Splash-Artworks.
abstract final class MyTubeColors {
  static const cream = Color(0xFFFDF8EA);
  static const creamDark = Color(0xFFF7E2C5);
  static const creamLight = Color(0xFFFFFCF4);
  static const navy = Color(0xFF072646);
  static const navyMuted = Color(0xFF496176);
  static const coral = Color(0xFFF24942);
  static const coralSoft = Color(0xFFFBC4BB);
  static const turquoise = Color(0xFF19BEB5);
  static const turquoiseSoft = Color(0xFFBFE9E0);
}

ThemeData buildMyTubeTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: MyTubeColors.coral,
        brightness: Brightness.light,
      ).copyWith(
        primary: MyTubeColors.coral,
        onPrimary: MyTubeColors.creamLight,
        primaryContainer: MyTubeColors.coralSoft,
        onPrimaryContainer: MyTubeColors.navy,
        secondary: MyTubeColors.turquoise,
        onSecondary: MyTubeColors.navy,
        secondaryContainer: MyTubeColors.turquoiseSoft,
        onSecondaryContainer: MyTubeColors.navy,
        surface: MyTubeColors.cream,
        onSurface: MyTubeColors.navy,
        onSurfaceVariant: MyTubeColors.navyMuted,
        surfaceContainerLowest: MyTubeColors.creamLight,
        surfaceContainerLow: MyTubeColors.creamLight,
        surfaceContainer: MyTubeColors.creamDark,
        surfaceContainerHigh: MyTubeColors.creamDark,
        outline: MyTubeColors.navyMuted,
        outlineVariant: MyTubeColors.creamDark,
        inverseSurface: MyTubeColors.navy,
        onInverseSurface: MyTubeColors.cream,
        inversePrimary: MyTubeColors.coralSoft,
        surfaceTint: MyTubeColors.coral,
      );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: MyTubeColors.cream,
    canvasColor: MyTubeColors.cream,
    useMaterial3: true,
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: MyTubeColors.navy,
      displayColor: MyTubeColors.navy,
    ),
    iconTheme: const IconThemeData(color: MyTubeColors.navy),
    appBarTheme: const AppBarTheme(
      backgroundColor: MyTubeColors.cream,
      foregroundColor: MyTubeColors.navy,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: MyTubeColors.creamLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: MyTubeColors.turquoise, width: 2),
      ),
    ),
    cardTheme: const CardThemeData(
      color: MyTubeColors.creamLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: MyTubeColors.creamLight,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: MyTubeColors.creamDark,
      indicatorColor: MyTubeColors.turquoiseSoft,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MyTubeColors.turquoise,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: MyTubeColors.coral,
      selectionColor: MyTubeColors.turquoiseSoft,
      selectionHandleColor: MyTubeColors.turquoise,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MyTubeColors.navy,
      contentTextStyle: TextStyle(color: MyTubeColors.creamLight),
      actionTextColor: MyTubeColors.turquoise,
    ),
    dividerColor: MyTubeColors.creamDark,
  );
}
