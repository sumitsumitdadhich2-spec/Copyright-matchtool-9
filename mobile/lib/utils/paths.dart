import 'dart:io';
import 'package:path/path.dart' as p;

/// 1:1 Port of lib/paths.ts
/// On-disk layout: DATA_DIR, SCANS_DIR, MEDIA_DIR, WORK_DIR, and budget limits.

class AppPaths {
  static final String dataDir = Platform.environment['DATA_DIR'] ?? p.join(Directory.current.path, 'data');
  static final String scansDir = p.join(dataDir, 'scans');
  static final String mediaDir = p.join(dataDir, 'media');
  static final String diskWorkDir = p.join(dataDir, 'work');
  static final String workDir = Platform.environment['WORK_DIR'] ?? p.join(dataDir, 'work-ram');

  /// RAM budget for WORK_DIR before jobs spill to disk (default 6 GB)
  static final int workRamBudgetBytes = (int.tryParse(Platform.environment['WORK_RAM_BUDGET_MB'] ?? '6144') ?? 6144) * 1024 * 1024;

  /// Storage cap for local media store (default 100 GB)
  static final int diskLimitBytes = ((double.tryParse(Platform.environment['DISK_LIMIT_GB'] ?? '100') ?? 100) * 1024 * 1024 * 1024).round();

  /// Keep at most this many scans (default 10)
  static final int maxScans = int.tryParse(Platform.environment['MAX_SCANS'] ?? '10') ?? 10;
}
