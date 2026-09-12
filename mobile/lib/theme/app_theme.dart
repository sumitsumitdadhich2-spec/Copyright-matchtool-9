import 'package:flutter/material.dart';

class AppTheme {
  // Cinematic media-forensics theme (1:1 port of app/globals.css)
  // Palette: near-black charcoal, graphite card, warm off-white text, amber "scanner" accent, signal green
  static const Color background = Color(0xFF17181D);
  static const Color surface = Color(0xFF1F2128);
  static const Color card = Color(0xFF1F2128);
  static const Color popover = Color(0xFF23252D);
  static const Color primary = Color(0xFFF59E0B); // Amber scanner accent
  static const Color primaryForeground = Color(0xFF1F1402);
  static const Color secondary = Color(0xFF292C36);
  static const Color secondaryForeground = Color(0xFFDFDFE3);
  static const Color accent = Color(0xFF432A10);
  static const Color accentForeground = Color(0xFFF59E0B);
  static const Color success = Color(0xFF22C55E); // Signal green
  static const Color error = Color(0xFFEF4444);
  static const Color destructive = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color border = Color(0xFF343743);
  static const Color input = Color(0xFF3E414F);
  static const Color textMuted = Color(0xFFA1A3AF);
  static const Color textForeground = Color(0xFFEDEEF0);

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: accent,
      surface: surface,
      error: error,
      onPrimary: primaryForeground,
      onSecondary: accentForeground,
      onSurface: textForeground,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: textForeground),
      titleTextStyle: TextStyle(
        color: textForeground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardTheme(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      labelStyle: const TextStyle(color: textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: primaryForeground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textForeground,
        side: const BorderSide(color: border, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 24,
    ),
  );
}
