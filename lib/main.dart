import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/language_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/database/database_manager.dart';
import 'core/theme/peadra_colors.dart';
import 'core/services/log_service.dart';
import 'features/auth/presentation/login_view.dart';
import 'core/utils/constants.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        sqfliteFfiInit();
      } catch (e) {
        stderr.writeln('sqfliteFfiInit failed: $e');
      }
      databaseFactory = databaseFactoryFfi;
    }

    final db = DatabaseManager.instance;
    await db.database;

    final maxBackupsStr = await db.getSetting('max_backups', defaultValue: defaultMaxBackups.toString());
    final maxBackups = int.tryParse(maxBackupsStr ?? '') ?? defaultMaxBackups;
    await db.backup(maxBackups: maxBackups);

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const PeadraApp(),
      ),
    );
  }, (error, stack) {
    LogService().error('Uncaught async error: $error', stack.toString());
  });
}

class PeadraApp extends StatelessWidget {
  const PeadraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final colors = PeadraTheme.getColors(themeProvider.themeName);

    return MaterialApp(
      title: 'Peadra',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: colors.accent,
        brightness: Brightness.light,
        scaffoldBackgroundColor: colors.bg,
        cardColor: colors.surface,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: colors.accent,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: colors.bg,
        cardColor: colors.surface,
      ),
      home: const LoginView(),
    );
  }
}
