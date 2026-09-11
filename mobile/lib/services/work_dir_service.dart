import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../utils/paths.dart';

/// 1:1 Port of lib/work-dir.ts
/// RAM working area for ffmpeg intermediates (movie chunks, short segments,
/// verifier clips, render parts, prescan / merge slices).
///
///   WORK_DIR         = tmpfs (/dev/shm/cmt)          — hot, RAM speed
///   DISK_WORK_DIR    = DATA_DIR/work (EBS)            — overflow fallback

class WorkPlacement {
  final String dir;
  final bool inRam;

  const WorkPlacement({required this.dir, required this.inRam});
}

class WorkDirService {
  static bool _booted = false;

  static void _ensure(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
  }

  /// Wipe stale work dirs (once per process boot).
  static void bootWorkDirs() {
    if (_booted) return;
    _booted = true;
    for (final d in [AppPaths.workDir, AppPaths.diskWorkDir]) {
      try {
        final dir = Directory(d);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        _ensure(d);
      } catch (err) {
        print('[work-dir] cannot create $d: $err');
      }
    }
    final mb = (AppPaths.workRamBudgetBytes / 1048576).toStringAsFixed(0);
    print('[work-dir] RAM work dir: ${AppPaths.workDir} (budget $mb MB), disk fallback: ${AppPaths.diskWorkDir}');
  }

  /// Recursive byte size of a directory (0 when missing).
  static int dirSize(String dirPath) {
    int total = 0;
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return 0;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += entity.lengthSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  /// Bytes currently used inside the RAM work dir.
  static int ramWorkUsed() {
    return dirSize(AppPaths.workDir);
  }

  /// Pick where a stage's output should go.
  static WorkPlacement placeWork(String scanId, String stage, int estimatedBytes) {
    bootWorkDirs();
    final used = ramWorkUsed();
    final fits = used + max(0, estimatedBytes) <= AppPaths.workRamBudgetBytes;
    final base = fits ? AppPaths.workDir : AppPaths.diskWorkDir;
    final dir = p.join(base, scanId, stage);
    _ensure(dir);
    if (!fits) {
      final estMb = (estimatedBytes / 1048576).toStringAsFixed(0);
      final usedMb = (used / 1048576).toStringAsFixed(0);
      print('[work-dir] $scanId/$stage: est $estMb MB exceeds RAM budget (used $usedMb MB) -> disk');
    }
    return WorkPlacement(dir: dir, inRam: fits);
  }

  /// Existing stage dir (RAM first, then disk) without creating anything.
  static String? findWork(String scanId, String stage) {
    for (final base in [AppPaths.workDir, AppPaths.diskWorkDir]) {
      final dir = p.join(base, scanId, stage);
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  /// Stage dir that exists, or a freshly placed one.
  static String stageDir(String scanId, String stage, int estimatedBytes) {
    return findWork(scanId, stage) ?? placeWork(scanId, stage, estimatedBytes).dir;
  }

  /// Remove one stage's work dir (both locations).
  static void removeStageWork(String scanId, String stage) {
    for (final base in [AppPaths.workDir, AppPaths.diskWorkDir]) {
      try {
        final dir = Directory(p.join(base, scanId, stage));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Remove everything a scan left in the work areas.
  static void removeScanWork(String scanId) {
    for (final base in [AppPaths.workDir, AppPaths.diskWorkDir]) {
      try {
        final dir = Directory(p.join(base, scanId));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Rough size estimate for a scan-copy encode (640px / 24 fps / CRF 28 ≈ 0.5 MB per second).
  static int estimateScanCopyBytes(double seconds) {
    return (max(1.0, seconds) * 0.5 * 1024 * 1024).ceil();
  }

  /// Rough size estimate for a bitrate-driven encode.
  static int estimateBitrateBytes(double seconds, int videoKbps, int audioKbps) {
    return ((max(1.0, seconds) * (videoKbps + audioKbps) * 1000) / 8).ceil();
  }
}
