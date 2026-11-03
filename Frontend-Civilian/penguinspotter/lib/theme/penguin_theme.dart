import 'package:flutter/material.dart';

/// The emperor penguin palette: tuxedo black and white, beak orange,
/// neck-patch yellow, and ice blue.
class PenguinColors {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const orange = Color(0xFFEB7D23);
  static const yellow = Color(0xFFF8E74C);
  static const blue = Color(0xFF5A7CF8);

  // Not new hues: white laid over black at ~9% and ~15%, for raised surfaces
  static const charcoal = Color(0xFF171717);
  static const charcoalHigh = Color(0xFF262626);
  static const muted = Color(0xB3FFFFFF); // white at 70%, for secondary text
  static const outline = Color(0x33FFFFFF); // white at 20%, for borders
}

/// "Midnight": black surfaces, yellow actions, orange alerts, blue links.
class PenguinTheme {
  static const _radius = BorderRadius.all(Radius.circular(14));

  static ThemeData midnight() {
    final scheme = ColorScheme.fromSeed(
      seedColor: PenguinColors.yellow,
      brightness: Brightness.dark,
    ).copyWith(
      primary: PenguinColors.yellow,
      onPrimary: PenguinColors.black,
      secondary: PenguinColors.blue,
      onSecondary: PenguinColors.white,
      tertiary: PenguinColors.orange,
      onTertiary: PenguinColors.black,
      error: PenguinColors.orange,
      onError: PenguinColors.black,
      surface: PenguinColors.black,
      onSurface: PenguinColors.white,
      onSurfaceVariant: PenguinColors.muted,
      surfaceContainer: PenguinColors.charcoal,
      surfaceContainerHigh: PenguinColors.charcoalHigh,
      outline: PenguinColors.outline,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: PenguinColors.black,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        bodyLarge: TextStyle(fontSize: 15),
        bodyMedium: TextStyle(fontSize: 14),
        // Small all-caps section headings, e.g. "ACCOUNT" on signup
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ).apply(
        bodyColor: PenguinColors.white,
        displayColor: PenguinColors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PenguinColors.black,
        foregroundColor: PenguinColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: PenguinColors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: const CardThemeData(
        color: PenguinColors.charcoal,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PenguinColors.charcoal,
        prefixIconColor: PenguinColors.muted,
        labelStyle: const TextStyle(color: PenguinColors.muted),
        hintStyle: const TextStyle(color: Color(0x66FFFFFF)),
        helperStyle: const TextStyle(color: PenguinColors.muted),
        floatingLabelStyle: const TextStyle(
          color: PenguinColors.yellow,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: const OutlineInputBorder(borderRadius: _radius),
        enabledBorder: const OutlineInputBorder(
          borderRadius: _radius,
          borderSide: BorderSide(color: PenguinColors.outline),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: _radius,
          borderSide: BorderSide(color: PenguinColors.yellow, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: PenguinColors.yellow,
          foregroundColor: PenguinColors.black,
          disabledBackgroundColor: PenguinColors.charcoalHigh,
          disabledForegroundColor: const Color(0x61FFFFFF),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const RoundedRectangleBorder(borderRadius: _radius),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PenguinColors.white,
          side: const BorderSide(color: PenguinColors.white, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: _radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: PenguinColors.blue,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: PenguinColors.orange,
        foregroundColor: PenguinColors.black,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: PenguinColors.yellow,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: PenguinColors.charcoalHigh,
        contentTextStyle: TextStyle(color: PenguinColors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: _radius),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: PenguinColors.charcoal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        titleTextStyle: TextStyle(
          color: PenguinColors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: PenguinColors.charcoal,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PenguinColors.charcoal,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: PenguinColors.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: PenguinColors.yellow,
        textColor: PenguinColors.white,
        shape: RoundedRectangleBorder(borderRadius: _radius),
      ),
    );
  }
}
