import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/scan_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

class ShivaMatchApp extends StatelessWidget {
  final SettingsService settingsService;
  final StorageService storageService;
  final ScanService scanService;

  const ShivaMatchApp({
    super.key,
    required this.settingsService,
    required this.storageService,
    required this.scanService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<StorageService>.value(value: storageService),
        ChangeNotifierProvider<ScanService>.value(value: scanService),
      ],
      child: MaterialApp(
        title: 'Shiva MatchTool',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
