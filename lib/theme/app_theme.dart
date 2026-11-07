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

  /// Text / icon colour on top of [accent] (dark for light accents).
  final Color onAccent;

  /// Main text / icon colour on the app background (white on dark themes,
  /// near-black on light ones).
  final Color text;

  /// True for light (white background) themes.
  final bool isLight;

  /// Big faint mark drawn over the whole app while this theme is selected
  /// (null = none). Used by the football-icon themes.
  final String? watermark;

  /// Faint black-and-white jersey stripes over the whole app.
  final bool stripes;

  /// Colour of those stripes (white for CR7, celeste for Messi).
  final Color stripeColor;

  /// Optional picture (an asset path) drawn faintly at the bottom of the
  /// screen. Nothing is shown when the file is missing.
  final String? backdropAsset;

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
    this.onAccent = Colors.white,
    this.text = Colors.white,
    this.isLight = false,
    this.watermark,
    this.stripes = false,
    this.stripeColor = Colors.white,
    this.backdropAsset,
  });
}

class Palettes {
  /// The original Deeprowss look: red on near-black.
  static const red = Palette(
    name: 'Deeprowss Red',
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

  static const rose = Palette(
    name: 'Rose',
    tagline: 'Soft pink glow on deep plum',
    bg: Color(0xFF12060E),
    panel: Color(0xFF1B0C16),
    card: Color(0xFF211019),
    cardDeep: Color(0xFF160912),
    accent: Color(0xFFFF4D8D),
    accentSoft: Color(0xFFFF9EC4),
    muted: Color(0xFFD1B3C2),
    dim: Color(0xFF93707F),
  );

  /// Argentina sky-blue with a touch of the golden sun.
  static const messi = Palette(
    name: 'Messi 10',
    tagline: 'Celeste sky blue, the Albiceleste spirit',
    bg: Color(0xFF060F1A),
    panel: Color(0xFF0C1A2A),
    card: Color(0xFF102235),
    cardDeep: Color(0xFF09141F),
    accent: Color(0xFF6CB4EE),
    accentSoft: Color(0xFFF6C85F),
    muted: Color(0xFFB4C6D8),
    dim: Color(0xFF74899E),
    onAccent: Color(0xFF06121E),
    watermark: 'MESSI 10',
    backdropAsset: 'assets/themes/messi.png',
  );

  /// Black-and-white striped jersey look with CR7 gold.
  static const cr7 = Palette(
    name: 'CR7',
    tagline: 'Jet black with champion gold',
    bg: Color(0xFF050505),
    panel: Color(0xFF0F0F0F),
    card: Color(0xFF171717),
    cardDeep: Color(0xFF0B0B0B),
    accent: Color(0xFFFFC62B),
    accentSoft: Color(0xFFF2F2F2),
    muted: Color(0xFFC9C9C9),
    dim: Color(0xFF7E7E7E),
    onAccent: Color(0xFF1A0C00),
    watermark: 'CR7',
    backdropAsset: 'assets/themes/cr7.png',
  );

  /// Clean white Facebook-style look: light grey feed background, white
  /// cards, Facebook blue accent.
  static const facebook = Palette(
    name: 'Facebook White',
    tagline: 'Clean white cards with classic blue',
    bg: Color(0xFFF0F2F5),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardDeep: Color(0xFFF0F2F5),
    accent: Color(0xFF1877F2),
    accentSoft: Color(0xFF2D88FF),
    muted: Color(0xFF65676B),
    dim: Color(0xFF8A8D91),
    line: Color(0xFFCED0D4),
    green: Color(0xFF31A24C),
    onAccent: Colors.white,
    text: Color(0xFF050505),
    isLight: true,
  );

  static const all = [red, ocean, emerald, rose, messi, cr7, facebook];

  /// Theme used until the user picks another one.
  static const defaultIndex = 6; // facebook
}

/// Design tokens. Values follow the active [Palette], so they are getters.
class Ui {
  static Palette palette = Palettes.facebook;

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
  static Color get text => palette.text;
  static bool get isLight => palette.isLight;

  /// Colour of unselected bottom-bar icons and labels (darker on light
  /// themes so they stay bold and readable).
  static Color get navOff => palette.isLight ? palette.muted : palette.dim;
  static const radius = 16.0;
}

/// Holds the selected theme, saves it, and repaints the whole app when it
/// changes (without losing the current screen).
class ThemeController {
  static final ValueNotifier<int> index = ValueNotifier<int>(Palettes.defaultIndex);

  static Future<void> load() async {
    final i = await Settings.themeIndex(Palettes.defaultIndex);
    _apply(i.clamp(0, Palettes.all.length - 1));
  }

  static void _apply(int i) {
    Ui.palette = Palettes.all[i];
    index.value = i;
    final icons = Ui.isLight ? Brightness.dark : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: Ui.isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Ui.panel,
      systemNavigationBarIconBrightness: icons,
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
  final light = Ui.isLight;
  final scheme = light
      ? ColorScheme.light(
          primary: Ui.red,
          onPrimary: Ui.palette.onAccent,
          secondary: Ui.redSoft,
          surface: Ui.panel,
          onSurface: Ui.text,
          error: const Color(0xFFE41E3F),
        )
      : ColorScheme.dark(
          primary: Ui.red,
          onPrimary: Ui.palette.onAccent,
          secondary: Ui.redSoft,
          surface: Ui.panel,
          onSurface: Colors.white,
          error: Ui.red,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: light ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ui.bg,
    splashFactory: InkRipple.splashFactory,
    dividerColor: Ui.line,
    dividerTheme: DividerThemeData(color: Ui.line),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? Ui.panel : Ui.bg,
      foregroundColor: Ui.text,
      surfaceTintColor: Colors.transparent,
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
          fontWeight: on ? FontWeight.w800 : FontWeight.w700,
          color: on ? (Ui.isLight ? Ui.red : Colors.white) : Ui.navOff,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        return IconThemeData(color: on ? Ui.red : Ui.navOff, size: 26);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ui.card,
      contentTextStyle: TextStyle(color: Ui.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Ui.panel,
      surfaceTintColor: Colors.transparent,
    ),
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
