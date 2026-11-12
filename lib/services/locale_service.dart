import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui_translator.dart';

class AppLanguage {
  final String code;
  final String native; // shown in the picker, in the language itself
  final String english;
  const AppLanguage(this.code, this.native, this.english);
}

/// App language: follows the phone's language until the user picks one in
/// the menu ("Automatic" goes back to following the phone).
class AppLocale {
  static const supported = <AppLanguage>[
    AppLanguage('en', 'English', 'English'),
    AppLanguage('fr', 'Français', 'French'),
    AppLanguage('es', 'Español', 'Spanish'),
    AppLanguage('pt', 'Português', 'Portuguese'),
    AppLanguage('ar', 'العربية', 'Arabic'),
    AppLanguage('sw', 'Kiswahili', 'Swahili'),
  ];

  static const auto = 'system';
  static const _key = 'footbolive_language';

  /// Language code in use right now.
  static final ValueNotifier<String> notifier = ValueNotifier<String>('en');

  static String _choice = auto;
  static _PhoneLocaleWatcher? _watcher;

  /// What the user picked: [auto] or a language code.
  static String get choice => _choice;
  static String get code => notifier.value;

  /// Language the fixed texts are shown in. Follows the phone's language
  /// (any language, not only the ones in [supported]) until the user picks
  /// one in the menu. [code] stays one of [supported] because the built-in
  /// Flutter widgets only ship for those.
  static String _ui = 'en';
  static String get uiLang => _ui;

  static bool _has(String c) => supported.any((l) => l.code == c);

  static String _fromPhone() {
    final phone = WidgetsBinding.instance.platformDispatcher.locales;
    for (final l in phone) {
      if (_has(l.languageCode)) return l.languageCode;
    }
    return 'en';
  }

  /// The phone's first language, whatever it is ('de', 'hi', 'ru' ...).
  static String _phoneAny() {
    final phone = WidgetsBinding.instance.platformDispatcher.locales;
    if (phone.isEmpty) return 'en';
    final c = phone.first.languageCode.toLowerCase();
    return c.isEmpty ? 'en' : c;
  }

  /// Language code for the translation service.
  static String gtxCode(String lang) {
    switch (lang) {
      case 'iw':
        return 'he';
      case 'in':
        return 'id';
      case 'fil':
        return 'tl';
      case 'nb':
      case 'nn':
        return 'no';
      case 'zh':
        final loc = WidgetsBinding.instance.platformDispatcher.locale;
        final trad = loc.scriptCode == 'Hant' ||
            loc.countryCode == 'TW' ||
            loc.countryCode == 'HK';
        return trad ? 'zh-TW' : 'zh-CN';
    }
    return lang;
  }

  static String _resolveUi() =>
      (_choice != auto && _has(_choice)) ? _choice : _phoneAny();

  static String _resolve() =>
      (_choice != auto && _has(_choice)) ? _choice : _fromPhone();

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _choice = prefs.getString(_key) ?? auto;
    notifier.value = _resolve();
    _ui = _resolveUi();
    await UiTranslator.prepare(_ui);
    _watcher ??= _PhoneLocaleWatcher();
    WidgetsBinding.instance.addObserver(_watcher!);
  }

  static Future<void> set(String choice) async {
    _choice = choice;
    await (await SharedPreferences.getInstance()).setString(_key, choice);
    await _apply();
  }

  static Future<void> _apply() async {
    final next = _resolve();
    final nextUi = _resolveUi();
    if (next == notifier.value && nextUi == _ui) return;
    _ui = nextUi;
    await UiTranslator.prepare(nextUi);
    notifier.value = next;
    refreshAll();
  }

  /// Strings are looked up while building, so mark every element for
  /// rebuild (same approach as ThemeController).
  static void refreshAll() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    root.visitChildren(mark);
  }
}

/// The phone's language changed while the app is open.
class _PhoneLocaleWatcher with WidgetsBindingObserver {
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (AppLocale.choice == AppLocale.auto) AppLocale._apply();
  }
}
