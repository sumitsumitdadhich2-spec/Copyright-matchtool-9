import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../models/chunk.dart';
import '../utils/paths.dart';
import '../utils/models.dart';
import 'scan_store_service.dart';

/// 1:1 Port of lib/store.ts
/// Primary Store Service for API keys, daily Gemini quota counters with Pacific timezone resets, scan state management, and log retention.

const int MAX_API_KEYS = 20;
const int LOG_MAX = 4000;
const int LOG_KEEP = 3500;

class StoreService {
  static String get _settingsFile => p.join(AppPaths.dataDir, 'settings.json');
  static String get _countersFile => p.join(AppPaths.dataDir, 'counters.json');

  static void _ensureDirs() {
    for (final d in [AppPaths.dataDir, AppPaths.scansDir, AppPaths.mediaDir]) {
      final dir = Directory(d);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
  }

  static T _readJson<T>(String filePath, T fallback) {
    final file = File(filePath);
    if (!file.existsSync()) return fallback;
    try {
      return jsonDecode(file.readAsStringSync()) as T;
    } catch (_) {
      return fallback;
    }
  }

  static void _writeJson(String filePath, dynamic data) {
    _ensureDirs();
    final file = File(filePath);
    final tmp = File('$filePath.tmp-${DateTime.now().millisecondsSinceEpoch}');
    tmp.writeAsStringSync(jsonEncode(data), flush: true);
    if (file.existsSync()) file.deleteSync();
    tmp.renameSync(filePath);
  }

  // ---------- Settings / API Keys ----------

  static String? getApiKeyN(int n) {
    final s = _readJson<Map<String, dynamic>>(_settingsFile, {});
    final field = n == 1 ? 'apiKey' : 'apiKey$n';
    return s[field]?.toString();
  }

  static String? getApiKey() => getApiKeyN(1);

  static List<String> getAllApiKeys() {
    final out = <String>[];
    for (int n = 1; n <= MAX_API_KEYS; n++) {
      final k = getApiKeyN(n);
      if (k != null && k.isNotEmpty && !out.contains(k)) {
        out.add(k);
      }
    }
    return out;
  }

  static void setApiKeyN(int n, String key) {
    final s = _readJson<Map<String, dynamic>>(_settingsFile, {});
    final field = n == 1 ? 'apiKey' : 'apiKey$n';
    s[field] = key;
    _writeJson(_settingsFile, s);
  }

  static void clearApiKeyN(int n) {
    final s = _readJson<Map<String, dynamic>>(_settingsFile, {});
    final field = n == 1 ? 'apiKey' : 'apiKey$n';
    s.remove(field);
    _writeJson(_settingsFile, s);
  }

  static String apiKeyHash(String apiKey) {
    final bytes = utf8.encode(apiKey);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 10);
  }

  // ---------- Daily Quota Counters (Pacific Time Midnight Reset) ----------

  static String geminiUsageDay([DateTime? date]) {
    final now = date ?? DateTime.now().toUtc().subtract(const Duration(hours: 7)); // PT approximation
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static bool checkDailyReset() {
    _ensureDirs();
    final counters = _readJson<Map<String, dynamic>>(_countersFile, {});
    final today = geminiUsageDay();
    final lastDay = counters['_lastActiveDay']?.toString();

    if (lastDay != null && lastDay != today) {
      final newCounters = <String, dynamic>{
        '_lastActiveDay': today,
        '_lastResetTime': DateTime.now().millisecondsSinceEpoch,
      };
      _writeJson(_countersFile, newCounters);
      return true;
    }

    if (counters['_lastActiveDay'] == null) {
      counters['_lastActiveDay'] = today;
      counters['_lastResetTime'] = DateTime.now().millisecondsSinceEpoch;
      _writeJson(_countersFile, counters);
    }
    return false;
  }

  static String _counterKey(String model, String apiKey) {
    return '$model|${geminiUsageDay()}|${apiKeyHash(apiKey)}';
  }

  static int getModelUsage(String model, String apiKey) {
    checkDailyReset();
    final counters = _readJson<Map<String, dynamic>>(_countersFile, {});
    return (counters[_counterKey(model, apiKey)] as num?)?.toInt() ?? 0;
  }

  static int incrementModelUsage(String model, String apiKey) {
    checkDailyReset();
    final counters = _readJson<Map<String, dynamic>>(_countersFile, {});
    final key = _counterKey(model, apiKey);
    final current = (counters[key] as num?)?.toInt() ?? 0;
    counters[key] = current + 1;

    // Prune keys from other days
    final today = geminiUsageDay();
    counters.removeWhere((k, v) => !k.startsWith('_') && !k.contains('|$today|'));

    _writeJson(_countersFile, counters);
    return current + 1;
  }

  static int decrementModelUsage(String model, String apiKey) {
    checkDailyReset();
    final counters = _readJson<Map<String, dynamic>>(_countersFile, {});
    final key = _counterKey(model, apiKey);
    final current = (counters[key] as num?)?.toInt() ?? 0;
    if (current > 0) {
      counters[key] = current - 1;
      _writeJson(_countersFile, counters);
      return current - 1;
    }
    return 0;
  }

  static void setModelExhausted(String model, String apiKey, int rpd) {
    checkDailyReset();
    final counters = _readJson<Map<String, dynamic>>(_countersFile, {});
    final key = _counterKey(model, apiKey);
    final current = (counters[key] as num?)?.toInt() ?? 0;
    counters[key] = [current, rpd].reduce((a, b) => a > b ? a : b);
    _writeJson(_countersFile, counters);
  }

  static void resetAllDailyCounters() {
    _ensureDirs();
    final today = geminiUsageDay();
    _writeJson(_countersFile, {
      '_lastActiveDay': today,
      '_lastResetTime': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---------- Scans & Logs ----------

  static List<LogEntry> trimLogs(List<LogEntry> logs) {
    if (logs.length <= LOG_MAX) return logs;
    int toDrop = logs.length - LOG_KEEP;
    final keep = List<bool>.filled(logs.length, true);

    // Oldest-first: drop info lines only
    for (int i = 0; i < logs.length && toDrop > 0; i++) {
      if (logs[i].level == LogLevel.info) {
        keep[i] = false;
        toDrop--;
      }
    }

    // Still too long: drop oldest remaining
    for (int i = 0; i < logs.length && toDrop > 0; i++) {
      if (keep[i]) {
        keep[i] = false;
        toDrop--;
      }
    }

    final out = <LogEntry>[];
    for (int i = 0; i < logs.length; i++) {
      if (keep[i]) out.add(logs[i]);
    }
    return out;
  }

  static void addLog(Scan scan, LogLevel level, String msg) {
    scan.logs.add(LogEntry(
      t: DateTime.now().millisecondsSinceEpoch,
      level: level,
      msg: msg,
    ));
    scan.logs = trimLogs(scan.logs);
  }
}
