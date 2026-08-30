import 'package:flutter/material.dart';

/// Central design system and theme definition for VitalSync.
///
/// Features a refined health & wellness visual language:
/// - Deep obsidian dark mode for high-contrast AMOLED/OLED presentation.
/// - Crisp, airy light mode with subtle slate surfaces.
/// - Semantic metric accent colors (Heart Rate, Steps, SpO2, Wellness).
/// - 18dp rounded card geometry with subtle border outlines.
abstract final class AppTheme {
  // Brand Primary & Accents
  static const Color primaryTeal = Color(0xFF00B4D8);
  static const Color primaryTealDark = Color(0xFF007791);

  // Semantic Metric Colors
  static const Color heartRateColor = Color(0xFFFF3366);
  static const Color stepsColor = Color(0xFF10B981);
  static const Color spo2Color = Color(0xFF0284C7);
  static const Color wellnessColor = Color(0xFF8B5CF6);
  static const Color watchAccentColor = Color(0xFF00B4D8);

  // Surface Colors — Dark Mode
  static const Color darkBackground = Color(0xFF0B0F17);
  static const Color darkSurface = Color(0xFF121824);
  static const Color darkSurfaceContainer = Color(0xFF192232);
  static const Color darkSurfaceContainerHigh = Color(0xFF212D40);
  static const Color darkOutline = Color(0xFF2A3950);

  // Surface Colors — Light Mode
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFF1F5F9);
  static const Color lightSurfaceContainerHigh = Color(0xFFE2E8F0);
  static const Color lightOutline = Color(0xFFCBD5E1);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryTeal,
      brightness: Brightness.light,
      surface: lightSurface,
      surfaceContainer: lightSurfaceContainer,
      outline: lightOutline,
      outlineVariant: lightSurfaceContainerHigh,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: lightBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: lightOutline.withValues(alpha: 0.6), width: 1),
        ),
        color: lightSurface,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: lightBackground,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0F172A),
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: lightSurface,
        indicatorColor: primaryTeal.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryTealDark);
          }
          return const IconThemeData(color: Color(0xFF64748B));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primaryTealDark,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: Color(0xFF64748B),
          );
        }),
      ),
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryTeal,
      brightness: Brightness.dark,
      surface: darkSurface,
      surfaceContainer: darkSurfaceContainer,
      outline: darkOutline,
      outlineVariant: darkSurfaceContainerHigh,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: darkOutline.withValues(alpha: 0.5), width: 1),
        ),
        color: darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: darkBackground,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFFF1F5F9),
          letterSpacing: -0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: darkSurface,
        indicatorColor: primaryTeal.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primaryTeal);
          }
          return const IconThemeData(color: Color(0xFF94A3B8));
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primaryTeal,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: Color(0xFF94A3B8),
          );
        }),
      ),
    );
  }
}
