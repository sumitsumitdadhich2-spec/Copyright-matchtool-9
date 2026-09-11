import 'package:flutter/material.dart';
import 'app.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/scan_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsService = SettingsService();
  await settingsService.init();

  final storageService = StorageService();
  await storageService.init();

  final scanService = ScanService();
  await scanService.init(storageService);

  runApp(
    ShivaMatchApp(
      settingsService: settingsService,
      storageService: storageService,
      scanService: scanService,
    ),
  );
}
