import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF713131);
  static const Color primaryLight = Color(0xFF8B4545);
  static const Color primaryDark = Color(0xFF4A1F1F);
  static const Color primaryFaded = Color(0x14713131);
  static const Color accent = Color(0xFFD4736C);
  static const Color accentLight = Color(0xFFE8A5A0);
  static const Color success = Color(0xFF5B8C5A);
  static const Color warning = Color(0xFFD4A04A);
  static const Color danger = Color(0xFFC0392B);
  static const Color background = Color(0xFFFFF8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHover = Color(0xFFFFF0EC);
  static const Color textColor = Color(0xFF2D1515);
  static const Color textSecondary = Color(0xFF7A5555);
  static const Color textLight = Color(0xFFA88080);
  static const Color border = Color(0xFFE8D0CC);
  static const Color borderLight = Color(0xFFF2E4E1);

  static ThemeData get theme => ThemeData(
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: accent,
          surface: surface,
          error: danger,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'serif',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 2,
          shadowColor: Color(0x1E713131),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: borderLight),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: borderLight, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: accent, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          labelStyle: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
        useMaterial3: true,
      );
}
