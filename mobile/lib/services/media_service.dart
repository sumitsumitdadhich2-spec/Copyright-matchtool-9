import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import 'storage_service.dart';

/// 1:1 Port of lib/media.ts
/// Local media management, cache deduplication, hard-link reuse, and storage sync.

class ReusableMedia {
  final String scanId;
  final String source; // 'disk' | 's3'
  final double? duration;

  ReusableMedia({
    required this.scanId,
    required this.source,
    this.duration,
  });
}

class MediaService {
  static String? _baseMediaDir;

  static void setBaseMediaDir(String dir) {
    _baseMediaDir = dir;
  }

  static String scanMediaDir(String scanId) {
    final base = _baseMediaDir ?? Directory.systemTemp.path;
    return p.join(base, 'media', scanId);
  }

  static String localMediaPath(String scanId, String kind) {
    return p.join(scanMediaDir(scanId), '$kind.mp4');
  }

  static int _fileSizeSafe(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Make sure the video exists locally
  static Future<String?> ensureLocalMedia(String id, String kind, {bool force = false}) async {
    final local = localMediaPath(id, kind);
    final file = File(local);
    if (!force && await file.exists() && (await file.length()) > 0) {
      return local;
    }
    return (await file.exists()) ? local : null;
  }

  /// Find a previous scan that holds THIS exact video (name + size match)
  static Future<ReusableMedia?> findReusableMedia({
    required StorageService storageService,
    required String kind,
    required String name,
    required int size,
    String? excludeId,
  }) async {
    if (name.isEmpty || size <= 0) return null;

    final scans = await storageService.loadScans();
    final candidates = scans.where((s) {
      if (s.id == excludeId) return false;
      if (kind == 'short') {
        return s.shortName == name && s.shortSize == size;
      } else {
        return s.movieName == name && s.movieSize == size;
      }
    }).toList();

    for (final s in candidates) {
      final local = localMediaPath(s.id, kind);
      if (_fileSizeSafe(local) == size) {
        return ReusableMedia(
          scanId: s.id,
          source: 'disk',
          duration: kind == 'short' ? s.shortDuration : s.movieDuration,
        );
      }
    }

    return null;
  }

  /// Re-use movie cut chunks if exact movie and trim range match
  static Future<Map<String, dynamic>> findAndReuseMovieChunks({
    required StorageService storageService,
    required String targetId,
    required String movieName,
    required int movieSize,
    required double trimStart,
    required double trimEnd,
    required int expectedCount,
  }) async {
    if (movieName.isEmpty || movieSize <= 0 || expectedCount <= 0) {
      return {'ok': false, 'count': 0};
    }

    final targetChunksDir = p.join(scanMediaDir(targetId), 'chunks');
    final scans = await storageService.loadScans();
    final candidates = scans.where((s) => s.id != targetId && s.movieName == movieName && s.movieSize == movieSize).toList();

    for (final cand in candidates) {
      final candStart = cand.movieTrimStart ?? 0.0;
      final candEnd = cand.movieTrimEnd ?? cand.movieDuration ?? 0.0;
      if ((candStart - trimStart).abs() >= 0.1 || (candEnd - trimEnd).abs() >= 0.1) continue;

      final candChunksDir = p.join(scanMediaDir(cand.id), 'chunks');
      final dir = Directory(candChunksDir);
      if (!await dir.exists()) continue;

      bool allExist = true;
      for (int i = 0; i < expectedCount; i++) {
        final chunkF = File(p.join(candChunksDir, 'chunk_$i.mp4'));
        if (!await chunkF.exists() || (await chunkF.length()) == 0) {
          allExist = false;
          break;
        }
      }
      if (!allExist) continue;

      try {
        final tDir = Directory(targetChunksDir);
        await tDir.create(recursive: true);
        int linked = 0;

        for (int i = 0; i < expectedCount; i++) {
          final srcP = p.join(candChunksDir, 'chunk_$i.mp4');
          final dstP = p.join(targetChunksDir, 'chunk_$i.mp4');
          final dstF = File(dstP);
          if (await dstF.exists() && (await dstF.length()) > 0) {
            linked++;
            continue;
          }
          try {
            await File(srcP).copy(dstP);
            linked++;
          } catch (_) {}
        }

        if (linked == expectedCount) {
          return {'ok': true, 'count': expectedCount, 'sourceId': cand.id};
        }
      } catch (_) {}
    }

    return {'ok': false, 'count': 0};
  }

  /// Re-use re-encoded 480p movie upload copy if exact movie and trim range match
  static Future<Map<String, dynamic>?> findAndReusePrescanMovie({
    required StorageService storageService,
    required String targetId,
    required String movieName,
    required int movieSize,
    required double trimStart,
    required double trimEnd,
  }) async {
    if (movieName.isEmpty || movieSize <= 0) return null;

    final scans = await storageService.loadScans();
    final candidates = scans.where((s) => s.id != targetId && s.movieName == movieName && s.movieSize == movieSize).toList();
    final targetCopy = p.join(scanMediaDir(targetId), 'prescan-movie.mp4');

    for (final cand in candidates) {
      final candStart = cand.movieTrimStart ?? 0.0;
      final candEnd = cand.movieTrimEnd ?? cand.movieDuration ?? 0.0;
      if ((candStart - trimStart).abs() >= 0.1 || (candEnd - trimEnd).abs() >= 0.1) continue;

      final candCopy = p.join(scanMediaDir(cand.id), 'prescan-movie.mp4');
      final candF = File(candCopy);
      if (!await candF.exists()) continue;
      final sz = await candF.length();
      if (sz < 1000 || sz > 1.95 * 1024 * 1024 * 1024) continue;

      try {
        final targetF = File(targetCopy);
        await targetF.parent.create(recursive: true);
        if (targetCopy != candCopy) {
          if (await targetF.exists()) await targetF.delete();
          await candF.copy(targetCopy);
        }
        final dur = cand.geminiPrescanMovieDuration ?? (cand.movieDuration ?? 0.0);
        return {
          'ok': true,
          'copyPath': targetCopy,
          'durationSec': dur,
          'sizeBytes': sz,
          'reencoded': cand.geminiPrescanMovieReencoded ?? false,
          'sourceId': cand.id,
        };
      } catch (_) {}
    }

    return null;
  }

  /// Check if the prescan movie is already active in Gemini Files API on this key
  static Map<String, dynamic>? findReusableGeminiMovieUpload({
    required List<Scan> allScans,
    required String movieName,
    required int movieSize,
    required String keyId,
    required double trimStart,
    required double trimEnd,
    String? excludeId,
  }) {
    if (movieName.isEmpty || movieSize <= 0) return null;

    final candidates = allScans.where((s) => s.id != excludeId && s.movieName == movieName && s.movieSize == movieSize).toList();

    for (final cand in candidates) {
      final candStart = cand.movieTrimStart ?? 0.0;
      final candEnd = cand.movieTrimEnd ?? cand.movieDuration ?? 0.0;
      if ((candStart - trimStart).abs() >= 0.1 || (candEnd - trimEnd).abs() >= 0.1) continue;

      final up = cand.prescanUploads.where((u) => u.keyId == keyId).firstOrNull;
      if (up != null && up.movieUri.isNotEmpty && up.movieName.isNotEmpty) {
        final age = DateTime.now().millisecondsSinceEpoch - up.uploadedAt;
        if (age < 47 * 3600 * 1000) {
          return {
            'movieUri': up.movieUri,
            'movieName': up.movieName,
            'uploadedAt': up.uploadedAt,
            'sourceId': cand.id,
          };
        }
      }
    }

    return null;
  }
}
