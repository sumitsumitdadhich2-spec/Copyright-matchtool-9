import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/scan.dart';

class StorageService extends ChangeNotifier {
  Directory? _appDir;
  Directory? _scansDir;
  List<Scan> _savedScans = [];

  List<Scan> get savedScans => _savedScans;

  Future<void> init() async {
    _appDir = await getApplicationDocumentsDirectory();
    _scansDir = Directory(p.join(_appDir!.path, 'scans'));
    if (!await _scansDir!.exists()) {
      await _scansDir!.create(recursive: true);
    }
    await loadScans();
  }

  Future<String> getScanDir(String scanId) async {
    final dir = Directory(p.join(_scansDir!.path, scanId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> getChunksDir(String scanId) async {
    final scanDir = await getScanDir(scanId);
    final chunksDir = Directory(p.join(scanDir, 'chunks'));
    if (!await chunksDir.exists()) {
      await chunksDir.create(recursive: true);
    }
    return chunksDir.path;
  }

  Future<void> saveScan(Scan scan) async {
    try {
      final scanDir = await getScanDir(scan.id);
      final metaFile = File(p.join(scanDir, 'scan_meta.json'));
      final jsonStr = jsonEncode(scan.toJson());
      await metaFile.writeAsString(jsonStr);

      final index = _savedScans.indexWhere((s) => s.id == scan.id);
      if (index >= 0) {
        _savedScans[index] = scan;
      } else {
        _savedScans.insert(0, scan);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[StorageService] Error saving scan: $e');
    }
  }

  Future<void> updateScanName(String scanId, String customName) async {
    final index = _savedScans.indexWhere((s) => s.id == scanId);
    if (index >= 0) {
      _savedScans[index].customName = customName.trim();
      await saveScan(_savedScans[index]);
    }
  }

  Future<void> loadScans() async {
    try {
      if (_scansDir == null || !await _scansDir!.exists()) return;
      final dirs = _scansDir!.listSync().whereType<Directory>();
      final List<Scan> loaded = [];

      for (final dir in dirs) {
        final metaFile = File(p.join(dir.path, 'scan_meta.json'));
        if (await metaFile.exists()) {
          try {
            final jsonStr = await metaFile.readAsString();
            final map = jsonDecode(jsonStr) as Map<String, dynamic>;
            loaded.add(Scan.fromJson(map));
          } catch (err) {
            debugPrint('[StorageService] Corrupt scan in ${dir.path}: $err');
          }
        }
      }

      loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _savedScans = loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('[StorageService] Error loading scans: $e');
    }
  }

  Future<void> deleteScan(String scanId) async {
    try {
      final scanDir = Directory(p.join(_scansDir!.path, scanId));
      if (await scanDir.exists()) {
        await scanDir.delete(recursive: true);
      }
      _savedScans.removeWhere((s) => s.id == scanId);
      notifyListeners();
    } catch (e) {
      debugPrint('[StorageService] Error deleting scan: $e');
    }
  }

  Future<void> clearAllScans() async {
    try {
      if (_scansDir != null && await _scansDir!.exists()) {
        await _scansDir!.delete(recursive: true);
        await _scansDir!.create(recursive: true);
      }
      _savedScans.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('[StorageService] Error clearing all scans: $e');
    }
  }

  Future<void> cleanChunks(String scanId) async {
    try {
      final chunksDir = Directory(p.join(_scansDir!.path, scanId, 'chunks'));
      if (await chunksDir.exists()) {
        await chunksDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[StorageService] Error cleaning chunks: $e');
    }
  }

  Future<int> getTotalStorageUsed() async {
    if (_scansDir == null || !await _scansDir!.exists()) return 0;
    int total = 0;
    try {
      final files = _scansDir!.listSync(recursive: true).whereType<File>();
      for (final file in files) {
        total += await file.length();
      }
    } catch (_) {}
    return total;
  }
}
