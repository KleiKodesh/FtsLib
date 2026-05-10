import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/main_screen.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);

  runApp(FtsLibDemoApp(settings: settings));
}

class FtsLibDemoApp extends StatelessWidget {
  final SettingsService settings;

  const FtsLibDemoApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'חיפוש בספרים',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E6DA4),
          brightness: Brightness.light,
        ),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: MainScreen(settings: settings),
    );
  }
}
