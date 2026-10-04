import 'package:flutter/material.dart';

/// Design tokens, carried over from the Footbolive web app (red on near-black).
class Ui {
  static const bg = Color(0xFF080B10);
  static const panel = Color(0xFF0F131A);
  static const card = Color(0xFF11151C);
  static const cardDeep = Color(0xFF0B0E14);
  static const red = Color(0xFFFF1744);
  static const redSoft = Color(0xFFFF637D);
  static const muted = Color(0xFFAEB6C3);
  static const dim = Color(0xFF777E89);
  static const line = Color(0x1FFFFFFF);
  static const green = Color(0xFF22E07A);
  static const radius = 16.0;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Ui.red,
    onPrimary: Colors.white,
    secondary: Ui.redSoft,
    surface: Ui.panel,
    onSurface: Colors.white,
    error: Ui.red,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ui.bg,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Ui.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Ui.panel,
      height: 68,
      elevation: 0,
      indicatorColor: Ui.red.withValues(alpha: .16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
          color: on ? Colors.white : Ui.dim,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(color: on ? Ui.red : Ui.dim, size: 26);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1B2030),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Ui.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
  );
}
