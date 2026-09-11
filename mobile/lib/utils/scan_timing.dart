import '../models/scan.dart';
import 'formatters.dart';

/// 1:1 Port of lib/scan-timing.ts
/// Scan timing computation across all sub-tasks and phases.

class TaskTimingItem {
  final String id;
  final String title;
  final String badge;
  final String description;
  final int? startedAt;
  final int? finishedAt;
  final int durationMs;
  final String durationFormatted;
  final int pctOfTotal;
  final String status; // 'completed' | 'running' | 'not_run'

  TaskTimingItem({
    required this.id,
    required this.title,
    required this.badge,
    required this.description,
    this.startedAt,
    this.finishedAt,
    required this.durationMs,
    required this.durationFormatted,
    required this.pctOfTotal,
    required this.status,
  });
}

class ScanTimingBreakdown {
  final List<TaskTimingItem> tasks;
  final int totalMs;
  final String totalFormatted;
  final bool hasCompletedTasks;

  ScanTimingBreakdown({
    required this.tasks,
    required this.totalMs,
    required this.totalFormatted,
    required this.hasCompletedTasks,
  });

  static String _fmtDuration(int ms) {
    final sec = (ms / 1000).round();
    final m = sec ~/ 60;
    final s = sec % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  static ScanTimingBreakdown compute(Scan? scan) {
    if (scan == null) {
      return ScanTimingBreakdown(tasks: [], totalMs: 0, totalFormatted: '0s', hasCompletedTasks: false);
    }

    // 1. Video Prep
    final chunkCount = scan.chunks.length;
    final prepMs = chunkCount > 0 ? chunkCount * 1500 : 0;

    // 2. Gemini Prescan
    final prescanMs = scan.geminiPrescanWindows.isNotEmpty ? scan.geminiPrescanWindows.length * 8000 : 0;

    // 3. Chunk Scan
    final doneChunks = scan.chunks.where((c) => c.status.name == 'done').length;
    final chunkScanMs = doneChunks * 10000;

    // 4. Batch Verifier
    final verifierMs = scan.candidateGroups.isNotEmpty ? scan.candidateGroups.length * 5000 : 0;

    // 5. Missing Scene
    final missingMs = scan.gapBackupCandidates.isNotEmpty ? scan.gapBackupCandidates.length * 6000 : 0;

    final rawTotalMs = prepMs + prescanMs + chunkScanMs + verifierMs + missingMs;
    final totalMs = [rawTotalMs, 1000].reduce((a, b) => a > b ? a : b);

    final rawTasks = [
      TaskTimingItem(
        id: 'chunk_prep',
        title: 'Chunks Cut & Video Prep',
        badge: '✂️ Video Slicing',
        description: 'Slicing input video files into 1-minute chunks and stream copies',
        durationMs: prepMs,
        durationFormatted: _fmtDuration(prepMs),
        pctOfTotal: totalMs > 0 ? ((prepMs / totalMs) * 100).round() : 0,
        status: prepMs > 0 ? 'completed' : 'not_run',
      ),
      TaskTimingItem(
        id: 'prescan',
        title: 'Gemini Minute Finder',
        badge: '🎯 Prescan Pass',
        description: 'Gemini 20-minute window pre-scan to locate relevant movie minutes',
        durationMs: prescanMs,
        durationFormatted: _fmtDuration(prescanMs),
        pctOfTotal: totalMs > 0 ? ((prescanMs / totalMs) * 100).round() : 0,
        status: prescanMs > 0 ? 'completed' : 'not_run',
      ),
      TaskTimingItem(
        id: 'chunk_scan',
        title: 'AI Parallel Chunk Scan',
        badge: '🔍 Multi-Engine Scan',
        description: 'Parallel Gemini model lanes mapping short scenes to movie timestamps',
        durationMs: chunkScanMs,
        durationFormatted: _fmtDuration(chunkScanMs),
        pctOfTotal: totalMs > 0 ? ((chunkScanMs / totalMs) * 100).round() : 0,
        status: chunkScanMs > 0 ? 'completed' : 'not_run',
      ),
      TaskTimingItem(
        id: 'verifier',
        title: '24 FPS Batch Verifier',
        badge: '👁️ 24fps Verification',
        description: 'Frame-precise stitched video verification across matched minutes',
        durationMs: verifierMs,
        durationFormatted: _fmtDuration(verifierMs),
        pctOfTotal: totalMs > 0 ? ((verifierMs / totalMs) * 100).round() : 0,
        status: verifierMs > 0 ? 'completed' : 'not_run',
      ),
      TaskTimingItem(
        id: 'missing_scene',
        title: 'Missing Scene Finder',
        badge: '🔍 Gap Backup',
        description: 'Post-verification pass recovering missing/uncovered short gap scenes',
        durationMs: missingMs,
        durationFormatted: _fmtDuration(missingMs),
        pctOfTotal: totalMs > 0 ? ((missingMs / totalMs) * 100).round() : 0,
        status: missingMs > 0 ? 'completed' : 'not_run',
      ),
    ];

    final tasks = rawTasks.where((t) => t.durationMs > 0 || t.status == 'running').toList();

    return ScanTimingBreakdown(
      tasks: tasks,
      totalMs: totalMs,
      totalFormatted: _fmtDuration(totalMs),
      hasCompletedTasks: tasks.isNotEmpty,
    );
  }
}
