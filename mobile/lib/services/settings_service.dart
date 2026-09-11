import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;
  String? _apiKey;
  String _selectedModel = AppConstants.defaultModel;
  bool _autoVerify = false;
  bool _keepChunks = false;

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.trim().isNotEmpty;
  String get selectedModel => _selectedModel;
  bool get autoVerify => _autoVerify;
  bool get keepChunks => _keepChunks;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _apiKey = _prefs?.getString(AppConstants.prefApiKey);
    _selectedModel = _prefs?.getString(AppConstants.prefSelectedModel) ?? AppConstants.defaultModel;
    _autoVerify = _prefs?.getBool(AppConstants.prefAutoVerify) ?? false;
    _keepChunks = _prefs?.getBool(AppConstants.prefKeepChunks) ?? false;
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    final clean = key.trim();
    _apiKey = clean;
    await _prefs?.setString(AppConstants.prefApiKey, clean);
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    _apiKey = null;
    await _prefs?.remove(AppConstants.prefApiKey);
    notifyListeners();
  }

  Future<void> setSelectedModel(String model) async {
    _selectedModel = model;
    await _prefs?.setString(AppConstants.prefSelectedModel, model);
    notifyListeners();
  }

  Future<void> setAutoVerify(bool value) async {
    _autoVerify = value;
    await _prefs?.setBool(AppConstants.prefAutoVerify, value);
    notifyListeners();
  }

  Future<void> setKeepChunks(bool value) async {
    _keepChunks = value;
    await _prefs?.setBool(AppConstants.prefKeepChunks, value);
    notifyListeners();
  }
}
