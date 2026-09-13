import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const ink = Color(0xFF20201D),
      paper = Color(0xFFFBFAF7),
      line = Color(0xFFE8E4DC),
      forest = Color(0xFF2F5145),
      sand = Color(0xFFF0ECE2);
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: paper,
    colorScheme: const ColorScheme.light(
      primary: forest,
      onPrimary: Colors.white,
      surface: paper,
      onSurface: ink,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: ink),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        color: Color(0xFF68665F),
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}
