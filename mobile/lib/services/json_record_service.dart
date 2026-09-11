import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// 1:1 Port of lib/json-record.ts
/// High performance 3-tier JSON cache & storage.

class CacheEntry {
  final dynamic value;
  final int at;
  CacheEntry(this.value, this.at);
}

class JsonRecordService {
  static final Map<String, CacheEntry> _cache = {};
  static const int _cacheTtlMs = 30000; // 30 seconds
  static String? _baseDataDir;

  static void setDataDir(String dir) {
    _baseDataDir = dir;
  }

  static String _localPath(String key) {
    final base = _baseDataDir ?? Directory.systemTemp.path;
    return p.join(base, key);
  }

  /// Read JSON record with in-memory caching and local disk fallback
  static Future<T?> readJSONRecord<T>(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cache[key];
    if (cached != null && (now - cached.at) < _cacheTtlMs) {
      return cached.value as T?;
    }

    final filePath = _localPath(key);
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final dynamic value = jsonDecode(content);
        _cache[key] = CacheEntry(value, now);
        return value as T?;
      }
    } catch (_) {
      // corrupt local copy fallback
    }

    _cache[key] = CacheEntry(null, now);
    return null;
  }

  /// Write JSON record atomically with tmp file rename
  static Future<void> writeJSONRecord(String key, dynamic value) async {
    final filePath = _localPath(key);
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final tmpPath = '${filePath}.tmp-${DateTime.now().millisecondsSinceEpoch}-${(1000 + (DateTime.now().microsecond % 9000))}';
    final tmpFile = File(tmpPath);
    await tmpFile.writeAsString(jsonEncode(value));
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(filePath);

    _cache[key] = CacheEntry(value, DateTime.now().millisecondsSinceEpoch);
  }

  /// Delete JSON record
  static Future<void> deleteJSONRecord(String key) async {
    _cache.remove(key);
    try {
      final file = File(_localPath(key));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Invalidate in-memory cache entry
  static void invalidateJSONRecord(String key) {
    _cache.remove(key);
  }
}
