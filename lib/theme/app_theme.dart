import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';

/// One complete colour set. `accent` is the brand colour (used where the
/// code says `Ui.red`), `accentSoft` its lighter companion.
class Palette {
  final String name;
  final String tagline;
  final Color bg;
  final Color panel;
  final Color card;
  final Color cardDeep;
  final Color accent;
  final Color accentSoft;
  final Color muted;
  final Color dim;
  final Color line;
  final Color green;

  const Palette({
    required this.name,
    required this.tagline,
    required this.bg,
    required this.panel,
    required this.card,
    required this.cardDeep,
    required this.accent,
    required this.accentSoft,
    required this.muted,
    required this.dim,
    this.line = const Color(0x1FFFFFFF),
    this.green = const Color(0xFF22E07A),
  });
}

class Palettes {
  /// The original Footbolive look: red on near-black.
  static const red = Palette(
    name: 'Footbolive Red',
    tagline: 'Classic red on midnight black',
    bg: Color(0xFF080B10),
    panel: Color(0xFF0F131A),
    card: Color(0xFF11151C),
    cardDeep: Color(0xFF0B0E14),
    accent: Color(0xFFFF1744),
    accentSoft: Color(0xFFFF637D),
    muted: Color(0xFFAEB6C3),
    dim: Color(0xFF777E89),
  );

  static const ocean = Palette(
    name: 'Ocean Blue',
    tagline: 'Deep navy with electric blue',
    bg: Color(0xFF050B16),
    panel: Color(0xFF0B1527),
    card: Color(0xFF0E1B30),
    cardDeep: Color(0xFF08111F),
    accent: Color(0xFF2979FF),
    accentSoft: Color(0xFF7FB0FF),
    muted: Color(0xFFA7B8D0),
    dim: Color(0xFF6C7F9A),
  );

  static const emerald = Palette(
    name: 'Emerald Pitch',
    tagline: 'Stadium green with a fresh glow',
    bg: Color(0xFF040C08),
    panel: Color(0xFF0A1710),
    card: Color(0xFF0D1D14),
    cardDeep: Color(0xFF07130D),
    accent: Color(0xFF00A86B),
    accentSoft: Color(0xFF4FDDA6),
    muted: Color(0xFFAAC0B3),
    dim: Color(0xFF72877B),
  );

  static const all = [red, ocean, emerald];
}

/// Design tokens. Values follow the active [Palette], so they are getters.
class Ui {
  static Palette palette = Palettes.red;

  static Color get bg => palette.bg;
  static Color get panel => palette.panel;
  static Color get card => palette.card;
  static Color get cardDeep => palette.cardDeep;
  static Color get red => palette.accent;
  static Color get redSoft => palette.accentSoft;
  static Color get muted => palette.muted;
  static Color get dim => palette.dim;
  static Color get line => palette.line;
  static Color get green => palette.green;
  static const radius = 16.0;
}

/// Holds the selected theme, saves it, and repaints the whole app when it
/// changes (without losing the current screen).
class ThemeController {
  static final ValueNotifier<int> index = ValueNotifier<int>(0);

  static Future<void> load() async {
    final i = await Settings.themeIndex();
    _apply(i.clamp(0, Palettes.all.length - 1));
  }

  static void _apply(int i) {
    Ui.palette = Palettes.all[i];
    index.value = i;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Ui.panel,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  static Future<void> set(int i) async {
    _apply(i);
    await Settings.setThemeIndex(i);
    // Many widgets read Ui.* directly, so mark every element for rebuild.
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.dark(
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
    appBarTheme: AppBarTheme(
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
      backgroundColor: Ui.card,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Ui.panel),
    drawerTheme: DrawerThemeData(backgroundColor: Ui.cardDeep),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Ui.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
  );
}
