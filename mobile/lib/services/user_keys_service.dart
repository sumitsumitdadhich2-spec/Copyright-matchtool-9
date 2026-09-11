import 'json_record_service.dart';

/// 1:1 Port of lib/user-keys.ts
/// PER-USER Gemini API keys, TwelveLabs keys, MinuteFinder modes, verifier toggle, and auto-mode settings.
/// Stored in auth/keys/<username>.json on local disk + S3.

const String KEYS_PREFIX = 'auth/keys/';
const int MAX_API_KEYS = 20;

const String TL_SLOT = 'twelvelabs';
const String MINUTE_FINDER_SLOT = 'minuteFinder';
const String VERIFIER_ENABLED_SLOT = 'verifierEnabled';
const String AUTO_MODE_SLOT = 'autoMode';

class UserKeysService {
  static String _cacheKey(String username) {
    return username.trim().toLowerCase();
  }

  static String _recordFor(String username) {
    return '$KEYS_PREFIX${_cacheKey(username)}.json';
  }

  static Future<Map<String, String>> _readUserKeys(String username) async {
    final data = await JsonRecordService.readJSONRecord<Map<String, dynamic>>(_recordFor(username));
    if (data == null) return {};
    return data.map((k, v) => MapEntry(k, v.toString()));
  }

  static Future<void> _writeUserKeys(String username, Map<String, String> keys) async {
    await JsonRecordService.writeJSONRecord(_recordFor(username), keys);
  }

  /// Read user's API key for slot n (1-20)
  static Future<String?> getUserKeyN(String username, int n) async {
    final keys = await _readUserKeys(username);
    return keys[n.toString()];
  }

  /// Save user's API key in slot n (1-20)
  static Future<void> setUserKeyN(String username, int n, String key) async {
    final keys = await _readUserKeys(username);
    keys[n.toString()] = key;
    await _writeUserKeys(username, keys);
  }

  /// Remove user's key in slot n
  static Future<void> clearUserKeyN(String username, int n) async {
    final keys = await _readUserKeys(username);
    keys.remove(n.toString());
    await _writeUserKeys(username, keys);
  }

  /// All configured keys in slot order, de-duplicated
  static Future<List<String>> getAllUserApiKeys(String username) async {
    final keys = await _readUserKeys(username);
    final out = <String>[];
    for (int n = 1; n <= MAX_API_KEYS; n++) {
      final k = keys[n.toString()];
      if (k != null && k.isNotEmpty && !out.contains(k)) {
        out.add(k);
      }
    }
    return out;
  }

  /// Twelve Labs API key
  static Future<String?> getUserTwelveLabsKey(String username) async {
    final keys = await _readUserKeys(username);
    return keys[TL_SLOT];
  }

  static Future<void> setUserTwelveLabsKey(String username, String key) async {
    final keys = await _readUserKeys(username);
    keys[TL_SLOT] = key;
    await _writeUserKeys(username, keys);
  }

  static Future<void> clearUserTwelveLabsKey(String username) async {
    final keys = await _readUserKeys(username);
    keys.remove(TL_SLOT);
    await _writeUserKeys(username, keys);
  }

  /// Minute Finder Mode: 'gemini' | 'twelvelabs' | 'off'
  static Future<String> getUserMinuteFinderMode(String username) async {
    final keys = await _readUserKeys(username);
    final v = keys[MINUTE_FINDER_SLOT];
    if (v == 'twelvelabs' || v == 'off') return v!;
    return 'gemini';
  }

  static Future<void> setUserMinuteFinderMode(String username, String mode) async {
    final keys = await _readUserKeys(username);
    keys[MINUTE_FINDER_SLOT] = mode;
    await _writeUserKeys(username, keys);
  }

  /// Verifier toggle
  static Future<bool> getUserVerifierEnabled(String username) async {
    final keys = await _readUserKeys(username);
    final v = keys[VERIFIER_ENABLED_SLOT];
    return v != 'false';
  }

  static Future<void> setUserVerifierEnabled(String username, bool enabled) async {
    final keys = await _readUserKeys(username);
    keys[VERIFIER_ENABLED_SLOT] = enabled ? 'true' : 'false';
    await _writeUserKeys(username, keys);
  }

  /// Auto Mode toggle
  static Future<bool> getUserAutoMode(String username) async {
    final keys = await _readUserKeys(username);
    final v = keys[AUTO_MODE_SLOT];
    return v != 'false';
  }

  static Future<void> setUserAutoMode(String username, bool enabled) async {
    final keys = await _readUserKeys(username);
    keys[AUTO_MODE_SLOT] = enabled ? 'true' : 'false';
    await _writeUserKeys(username, keys);
  }

  /// Delete user's entire key file
  static Future<void> deleteUserKeys(String username) async {
    await JsonRecordService.deleteJSONRecord(_recordFor(username));
  }
}
