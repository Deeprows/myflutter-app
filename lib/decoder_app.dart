import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/app_lock_screen.dart';
import 'screens/decoder/decoder_hub_screen.dart';
import 'screens/movies_screen.dart';
import 'screens/plans_screen.dart';
import 'screens/tv_screen.dart';
import 'services/app_nav.dart';
import 'services/locale_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_watermark.dart';
import 'widgets/launch_splash.dart';

class DecoderApp extends StatelessWidget {
 const DecoderApp({super.key});
 @override Widget build(BuildContext context) => ValueListenableBuilder<int>(
  valueListenable: ThemeController.index,
  builder: (_, _, _) => ValueListenableBuilder<String>(
   valueListenable: AppLocale.notifier,
   builder: (_, lang, _) => MaterialApp(
    title: 'Deeprowss Decoder', locale: Locale(lang),
    supportedLocales: [for (final l in AppLocale.supported) Locale(l.code)],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    debugShowCheckedModeBanner: false, navigatorKey: AppNav.key,
    scaffoldMessengerKey: PushService.messengerKey, theme: buildTheme(),
    builder: (context, child) => LaunchSplash(child: AppLockOverlay(child: Stack(
     fit: StackFit.expand, children: [child ?? const SizedBox.shrink(), const ThemeWatermark()],
    ))),
    home: const DecoderHome(),
   ),
  ),
 );
}
class DecoderHome extends StatefulWidget {
 const DecoderHome({super.key});
 @override State<DecoderHome> createState() => _DecoderHomeState();
}
class _DecoderHomeState extends State<DecoderHome> {
 int tab = 0;
 Widget get page => switch (tab) {
  0 => const TvScreen(),
  1 => const MoviesScreen(),
  2 => const DecoderHubScreen(),
  _ => const PlansScreen(),
 };
 static const items = <NavigationDestination>[
  NavigationDestination(icon: Icon(Icons.live_tv_outlined), selectedIcon: Icon(Icons.live_tv), label: 'TV'),
  NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Movies'),
  NavigationDestination(icon: Icon(Icons.cast_outlined), selectedIcon: Icon(Icons.cast_connected), label: 'Decoder'),
  NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium), label: 'Premium'),
 ];
 @override Widget build(BuildContext context) => Scaffold(
  body: page,
  bottomNavigationBar: NavigationBar(selectedIndex: tab, destinations: items, onDestinationSelected: (v) => setState(() => tab = v)),
 );
}
