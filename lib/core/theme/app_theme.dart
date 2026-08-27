import 'package:flutter/material.dart';

/// Central theme definition for VitalSync.
///
/// Keeps the UI minimal, modern, and data-focused as required by the
/// product spec: Material 3, no unnecessary gradients or decoration.
abstract final class AppTheme {
  static const Color _seedColor = Color(0xFF2E7D6B);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
