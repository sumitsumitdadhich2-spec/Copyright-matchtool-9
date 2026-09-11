import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class KeySlotInfo {
  final int index;
  final bool hasKey;
  final String? maskedKey;
  final String? rawKey;
  final Map<String, int> usage;
  final int totalRequests;

  KeySlotInfo({
    required this.index,
    required this.hasKey,
    this.maskedKey,
    this.rawKey,
    required this.usage,
    required this.totalRequests,
  });
}

class SettingsService extends ChangeNotifier {
  static const int maxSlots = 20;

  SharedPreferences? _prefs;
  final List<String?> _keys = List.filled(maxSlots, null);
  final List<Map<String, int>> _keyUsage = List.generate(maxSlots, (_) => {});
  final List<int> _keyTotalRequests = List.filled(maxSlots, 0);

  String? _twelveLabsKey;
  String _selectedModel = AppConstants.defaultModel;
  bool _autoVerify = false;
  bool _keepChunks = false;

  String? get apiKey => _keys[0]; // Slot 1 is default
  bool get hasApiKey => _keys.any((k) => k != null && k.trim().isNotEmpty);
  int get activeKeyCount => _keys.where((k) => k != null && k.trim().isNotEmpty).length;

  List<String> get allValidKeys => _keys.whereType<String>().where((k) => k.trim().isNotEmpty).toList();

  String? getKey(int slot1Indexed) {
    if (slot1Indexed < 1 || slot1Indexed > maxSlots) return null;
    return _keys[slot1Indexed - 1];
  }

  String? get twelveLabsKey => _twelveLabsKey;
  bool get hasTwelveLabsKey => _twelveLabsKey != null && _twelveLabsKey!.trim().isNotEmpty;
  String? get maskedTwelveLabsKey => _maskKey(_twelveLabsKey);

  String get selectedModel => _selectedModel;
  bool get autoVerify => _autoVerify;
  bool get keepChunks => _keepChunks;

  List<KeySlotInfo> get slots {
    return List.generate(maxSlots, (i) {
      final key = _keys[i];
      return KeySlotInfo(
        index: i + 1,
        hasKey: key != null && key.trim().isNotEmpty,
        maskedKey: _maskKey(key),
        rawKey: key,
        usage: _keyUsage[i],
        totalRequests: _keyTotalRequests[i],
      );
    });
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // Load legacy key into slot 1 if exists
    final legacyKey = _prefs?.getString(AppConstants.prefApiKey);
    if (legacyKey != null && legacyKey.isNotEmpty) {
      _keys[0] = legacyKey;
    }

    // Load 20 keys
    for (int i = 0; i < maxSlots; i++) {
      final k = _prefs?.getString('gemini_api_key_${i + 1}');
      if (k != null && k.isNotEmpty) {
        _keys[i] = k;
      }
      _keyTotalRequests[i] = _prefs?.getInt('gemini_key_reqs_${i + 1}') ?? 0;
    }

    _twelveLabsKey = _prefs?.getString('twelvelabs_api_key');
    _selectedModel = _prefs?.getString(AppConstants.prefSelectedModel) ?? AppConstants.defaultModel;
    _autoVerify = _prefs?.getBool(AppConstants.prefAutoVerify) ?? false;
    _keepChunks = _prefs?.getBool(AppConstants.prefKeepChunks) ?? false;
    notifyListeners();
  }

  Future<void> saveKey(int slot1Indexed, String key) async {
    if (slot1Indexed < 1 || slot1Indexed > maxSlots) return;
    final clean = key.trim();
    final idx = slot1Indexed - 1;
    _keys[idx] = clean.isEmpty ? null : clean;

    if (clean.isEmpty) {
      await _prefs?.remove('gemini_api_key_$slot1Indexed');
      if (slot1Indexed == 1) await _prefs?.remove(AppConstants.prefApiKey);
    } else {
      await _prefs?.setString('gemini_api_key_$slot1Indexed', clean);
      if (slot1Indexed == 1) await _prefs?.setString(AppConstants.prefApiKey, clean);
    }
    notifyListeners();
  }

  Future<void> removeKey(int slot1Indexed) async {
    await saveKey(slot1Indexed, '');
  }

  Future<void> setApiKey(String key) async {
    await saveKey(1, key);
  }

  Future<void> clearApiKey() async {
    await removeKey(1);
  }

  Future<void> setTwelveLabsKey(String key) async {
    final clean = key.trim();
    _twelveLabsKey = clean.isEmpty ? null : clean;
    if (clean.isEmpty) {
      await _prefs?.remove('twelvelabs_api_key');
    } else {
      await _prefs?.setString('twelvelabs_api_key', clean);
    }
    notifyListeners();
  }

  Future<void> clearTwelveLabsKey() async {
    await setTwelveLabsKey('');
  }

  Future<int> bulkPasteKeys(String multiline) async {
    final lines = multiline
        .split(RegExp(r'[\r\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && (s.startsWith('AIza') || s.length >= 30))
        .toList();

    int added = 0;
    for (int i = 0; i < maxSlots && added < lines.length; i++) {
      if (_keys[i] == null || _keys[i]!.isEmpty) {
        await saveKey(i + 1, lines[added]);
        added++;
      }
    }
    return added;
  }

  void recordUsage(int slot1Indexed, String modelId) {
    if (slot1Indexed < 1 || slot1Indexed > maxSlots) return;
    final idx = slot1Indexed - 1;
    _keyUsage[idx][modelId] = (_keyUsage[idx][modelId] ?? 0) + 1;
    _keyTotalRequests[idx]++;
    _prefs?.setInt('gemini_key_reqs_$slot1Indexed', _keyTotalRequests[idx]);
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

  String? _maskKey(String? key) {
    if (key == null || key.isEmpty) return null;
    if (key.length <= 10) return '••••••••';
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }
}
