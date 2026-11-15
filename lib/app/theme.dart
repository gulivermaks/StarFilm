import 'package:flutter/material.dart';

class StarFilmColors {
  const StarFilmColors._();

  static const Color background = Color(0xFF0B0D11);
  static const Color surface = Color(0xFF15191F);
  static const Color surfaceElevated = Color(0xFF1C222B);
  static const Color border = Color(0xFF28303D);
  static const Color lime = Color(0xFF80C004);
  static const Color limeFocus = Color(0xFF9BE405);
  static const Color onLime = Color(0xFF0B0D11);
  static const Color textPrimary = Color(0xFFF3F5F8);
  static const Color textSecondary = Color(0xFFA7B0BE);
  static const Color error = Color(0xFFE5534B);
  static const Color warning = Color(0xFFE3A008);
  static const Color success = Color(0xFF80C004);
}

ThemeData buildStarFilmTheme() {
  const scheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: StarFilmColors.lime,
    onPrimary: StarFilmColors.onLime,
    secondary: StarFilmColors.limeFocus,
    onSecondary: StarFilmColors.onLime,
    surface: StarFilmColors.surface,
    onSurface: StarFilmColors.textPrimary,
    error: StarFilmColors.error,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: StarFilmColors.background,
    cardTheme: CardThemeData(
      color: StarFilmColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: StarFilmColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StarFilmColors.background,
      foregroundColor: StarFilmColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StarFilmColors.surface,
      indicatorColor: StarFilmColors.lime,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: StarFilmColors.onLime);
        }
        return const IconThemeData(color: StarFilmColors.textSecondary);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: StarFilmColors.limeFocus,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }
        return const TextStyle(
          color: StarFilmColors.textSecondary,
          fontSize: 12,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StarFilmColors.lime,
        foregroundColor: StarFilmColors.onLime,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StarFilmColors.textPrimary,
        side: const BorderSide(color: StarFilmColors.border),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StarFilmColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: StarFilmColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: StarFilmColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: StarFilmColors.limeFocus, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: StarFilmColors.surfaceElevated,
      selectedColor: StarFilmColors.lime,
      labelStyle: const TextStyle(color: StarFilmColors.textPrimary),
      secondaryLabelStyle: const TextStyle(
        color: StarFilmColors.onLime,
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: StarFilmColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: StarFilmColors.border),
  );
}
