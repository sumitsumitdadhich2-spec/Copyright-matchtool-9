import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../utils/paths.dart';

/// 1:1 Port of lib/scan-store.ts
/// Local disk scan persistence with atomic writes, throttling, and optional remote sync.

class ScanStoreService {
  static const int throttleMs = 15000;
  static final Map<String, int> _lastUpload = {};
  static final Map<String, String> _latestPayload = {};

  static String scanJsonPath(String scanId) {
    return p.join(AppPaths.scansDir, '$scanId.json');
  }

  /// Save scan JSON atomically to local disk
  static Future<void> saveScanLocal(Scan scan) async {
    final file = File(scanJsonPath(scan.id));
    await file.parent.create(recursive: true);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(jsonEncode(scan.toJson()), flush: true);
    if (file.existsSync()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  /// Read single scan JSON
  static Future<Scan?> readScanLocal(String scanId) async {
    final file = File(scanJsonPath(scanId));
    if (!file.existsSync()) return null;
    try {
      final text = await file.readAsString();
      final json = jsonDecode(text);
      return Scan.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// List all local scans
  static Future<List<Scan>> listScansLocal() async {
    final dir = Directory(AppPaths.scansDir);
    if (!dir.existsSync()) return [];
    final scans = <Scan>[];
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final text = entity.readAsStringSync();
          scans.add(Scan.fromJson(jsonDecode(text)));
        } catch (_) {}
      }
    }
    scans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return scans;
  }

  /// Delete scan record locally
  static Future<void> deleteScanLocal(String scanId) async {
    final file = File(scanJsonPath(scanId));
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
