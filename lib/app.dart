import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/shell_screen.dart';
import 'theme/app_theme.dart';

class FootboliveApp extends StatelessWidget {
  const FootboliveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const ShellScreen(),
    );
  }
}
