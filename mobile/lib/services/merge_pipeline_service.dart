import 'dart:io';
import '../models/scan.dart';
import 'storage_service.dart';
import 'media_service.dart';
import 'merge_service.dart';

/// 1:1 Port of lib/merge-pipeline.ts
/// Auto pipeline orchestrator for video merging, duration verification, and step state tracking.

class MergePipelineService {
  static final Set<String> _running = {};

  static bool isPipelineRunning(String id) => _running.contains(id);

  static bool pipelineReady(Scan scan) {
    return (scan.shortDuration != null &&
        scan.movieDuration != null &&
        scan.awaitingTrim == false);
  }

  static String _fmtDur(double sec) {
    final s = sec.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m ${ss.toString().padLeft(2, '0')}s' : '${m}m ${ss}s';
  }

  /// Kick off or retry the merge pipeline
  static Future<Map<String, dynamic>> startMergePipeline({
    required StorageService storageService,
    required String scanId,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};
    if (!pipelineReady(scan)) {
      return {
        'ok': false,
        'error': 'Short + movie dono upload + trim confirm hone ke baad hi pipeline chalti hai.'
      };
    }
    if (_running.contains(scanId)) {
      return {'ok': false, 'error': 'Pipeline already running'};
    }

    _running.add(scanId);

    scan.pipelineStatus = 'checking';
    scan.pipelineProgress = 'Checking codec/resolution...';
    scan.pipelineError = null;
    await storageService.updateScan(scan);

    // Run async in background
    runPipelineAsync(storageService, scanId).then((_) {
      _running.remove(scanId);
    }).catchError((err) async {
      _running.remove(scanId);
      final s = (await storageService.loadScans()).where((x) => x.id == scanId).firstOrNull;
      if (s != null) {
        s.pipelineStatus = 'error';
        s.pipelineError = err.toString();
        await storageService.updateScan(s);
      }
    });

    return {'ok': true};
  }

  static Future<void> runPipelineAsync(StorageService storageService, String id) async {
    final scans = await storageService.loadScans();
    final scan0 = scans.where((s) => s.id == id).firstOrNull;
    if (scan0 == null || scan0.shortDuration == null || scan0.movieDuration == null) {
      throw Exception('Scan/media state missing');
    }

    final shortDuration = scan0.shortDuration!;
    final movieDuration = scan0.movieDuration!;
    final mediaDir = MediaService.scanMediaDir(id);
    final mergedFile = MergeService.mergedFilePath(mediaDir);

    final shortFile = await MediaService.ensureLocalMedia(id, 'short');
    final movieFile = await MediaService.ensureLocalMedia(id, 'movie');

    if (shortFile == null || movieFile == null || !File(shortFile).existsSync() || !File(movieFile).existsSync()) {
      throw Exception('Short/movie file server par nahi mili — dobara upload karke retry karo.');
    }

    // Merge stage
    final expectedDuration = shortDuration + movieDuration;
    final cachedMergeOk = File(mergedFile).existsSync() && File(mergedFile).lengthSync() > 0;

    if (cachedMergeOk) {
      scan0.pipelineStatus = 'merging';
      scan0.pipelineProgress = 'Merged file cached — ready';
      await storageService.updateScan(scan0);
    } else {
      scan0.pipelineStatus = 'merging';
      scan0.pipelineProgress = 'Merging PART A + PART B (precise re-encode)...';
      await storageService.updateScan(scan0);

      await MergeService.mergeVideos(
        shortFile: shortFile,
        movieFile: movieFile,
        outFile: mergedFile,
        scanId: id,
        onProgress: (pct, note) async {
          final cur = (await storageService.loadScans()).where((x) => x.id == id).firstOrNull;
          if (cur != null) {
            cur.pipelineProgress = 'Merging $pct% — $note';
            await storageService.updateScan(cur);
          }
        },
      );
    }

    final sFinal = (await storageService.loadScans()).where((x) => x.id == id).firstOrNull;
    if (sFinal != null) {
      sFinal.pipelineStatus = 'done';
      sFinal.pipelineProgress = 'Pipeline merge ready (${_fmtDur(expectedDuration)})';
      await storageService.updateScan(sFinal);
    }
  }
}
