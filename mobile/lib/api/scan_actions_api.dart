import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../models/chunk.dart';
import '../services/storage_service.dart';
import '../services/session_service.dart';
import '../services/render_service.dart';
import '../services/scheduler_service.dart';
import '../services/batch_verifier_service.dart';
import '../services/store_service.dart';
import '../services/user_keys_service.dart';
import '../services/token_service.dart';
import '../services/media_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../services/gemini_minute_finder_service.dart';
import '../services/missing_scene_scanner_service.dart';
import '../services/gap_backup_service.dart';
import '../services/merge_pipeline_service.dart';
import '../services/background_queue_service.dart';
import '../services/twelvelabs_service.dart';
import '../services/users_service.dart';
import '../utils/candidate_pick.dart';
import '../utils/formatters.dart';
import '../utils/minute_ranges.dart';
import '../utils/render_segments.dart';
import '../utils/short_coverage.dart';
import '../utils/segment_range.dart';
import '../utils/constants.dart';

/// 1:1 Port of app/api/scans/[id]/ endpoints:
/// - batch-verify
/// - candidates/pick
/// - chunks/[index]/retry
/// - gap-backup
/// - media
/// - merge-pipeline/approve
/// - merge-pipeline
/// - minute-finder
/// - missing-scene-scan
/// - render/cancel
/// - render/download
/// - render

class ScanApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;
  final Map<String, String>? headers;
  final String? filePath;
  final int? fileStart;
  final int? fileEnd;
  final int? fileSize;
  final String? statusText;

  ScanApiResponse({
    required this.statusCode,
    required this.data,
    this.headers,
    this.filePath,
    this.fileStart,
    this.fileEnd,
    this.fileSize,
    this.statusText,
  });
}

class ScanActionsApi {
  static bool _canAccess(SessionUser session, Scan scan) {
    return session.role == 'admin' || scan.ownerUsername == session.username;
  }

  // =========================================================================
  // 1. CHUNKS RETRY: POST /api/scans/[id]/chunks/[index]/retry
  // =========================================================================

  static Future<ScanApiResponse> retryChunk({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String? sessionToken,
    required String scanId,
    required int chunkIndex,
    int? segmentIndex,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'ok': false, 'error': 'Unauthorized'});

    if (chunkIndex < 0) {
      return ScanApiResponse(statusCode: 400, data: {'ok': false, 'error': 'Invalid chunk index'});
    }
    if (segmentIndex != null && segmentIndex < 0) {
      return ScanApiResponse(statusCode: 400, data: {'ok': false, 'error': 'Invalid segment index'});
    }

    final userApiKeys = await UserKeysService.getAllUserApiKeys(session.username);
    final result = await SchedulerService.retryChunk(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      chunkIndex: chunkIndex,
      segmentIndex: segmentIndex,
      userApiKeys: userApiKeys,
    );

    return ScanApiResponse(
      statusCode: result['ok'] == true ? 200 : 400,
      data: result,
    );
  }

  // =========================================================================
  // 2. GAP BACKUP: GET & POST /api/scans/[id]/gap-backup
  // =========================================================================

  static Future<ScanApiResponse> getGapBackup({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    final gaps = GapBackupService.uncovered(scan);
    final coverage = ShortCoverageUtils.coverageFromRanges(
      scan.matches.map((m) => ShortRange(start: m.shortStart, end: m.shortEnd)).toList(),
      scan.shortDuration ?? 0.0,
    );

    return ScanApiResponse(
      statusCode: 200,
      data: {
        'coverage': coverage.toJson(),
        'gaps': gaps.map((g) => {'start': g.start, 'end': g.end}).toList(),
        'state': scan.gapBackup?.toJson() ?? {
          'status': 'idle',
          'parts': [],
          'minutes': [],
          'requests': [],
          'candidates': [],
          'addedMatches': [],
          'requestCount': 0,
          'tokenCount': 0,
        },
        'running': GapBackupService.isRunning(scanId),
      },
    );
  }

  static Future<ScanApiResponse> postGapBackup({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
    String? action,
    String? candidateId,
    List<String>? models,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (action == 'stop') {
      GapBackupService.stop(scanId);
      return ScanApiResponse(statusCode: 200, data: {'ok': true});
    }

    if ((action == 'accept' || action == 'reject') && candidateId != null) {
      final success = await GapBackupService.reviewGapCandidate(
        scan: scan,
        storageService: storageService,
        candidateId: candidateId,
        decision: action!,
      );
      return ScanApiResponse(
        statusCode: success ? 200 : 404,
        data: success ? {'ok': true} : {'ok': false, 'error': 'Candidate not found'},
      );
    }

    final keys = await UserKeysService.getAllUserApiKeys(session.username);
    if (keys.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Gemini API key nahi hai — Settings me apni key add karo.'});
    }

    if (GapBackupService.isRunning(scanId)) {
      return ScanApiResponse(statusCode: 409, data: {'error': 'Gap backup already running'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 3. MEDIA: GET /api/scans/[id]/media
  // =========================================================================

  static Future<ScanApiResponse> getMedia({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required String? sessionToken,
    required String scanId,
    String? kind,
    String? rangeHeader,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'}, statusText: 'Unauthorized');
    }

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Not found'}, statusText: 'Not found');
    }

    final normalizedKind = kind == 'short' ? 'short' : 'movie';
    final file = await MediaService.ensureLocalMedia(scanId, normalizedKind);
    if (file == null || !File(file).existsSync()) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'File not found'}, statusText: 'File not found');
    }

    String streamFile = file;
    final mediaDir = MediaService.scanMediaDir(scanId);

    if (normalizedKind == 'movie') {
      final previewFile = p.join(mediaDir, 'preview-movie.mp4');
      final prescanFile = p.join(mediaDir, 'prescan-movie.mp4');
      final pF = File(previewFile);
      final psF = File(prescanFile);
      final origSize = File(file).lengthSync();

      if (pF.existsSync() && pF.lengthSync() > 1000) {
        streamFile = previewFile;
      } else if (psF.existsSync() && psF.lengthSync() > 1000 && psF.lengthSync() < origSize * 0.75) {
        streamFile = prescanFile;
      } else {
        ffmpegService.triggerFastPreview(file, previewFile);
      }
    }

    final f = File(streamFile);
    final stat = f.statSync();
    final totalSize = stat.size;
    final etag = '"$totalSize-${stat.modified.millisecondsSinceEpoch}"';

    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (m != null) {
        final start = int.parse(m.group(1)!);
        const chunkSize = 16 * 1024 * 1024;
        final end = (m.group(2) != null && m.group(2)!.isNotEmpty)
            ? min(int.parse(m.group(2)!), totalSize - 1)
            : min(start + chunkSize - 1, totalSize - 1);

        if (start >= totalSize) {
          return ScanApiResponse(
            statusCode: 416,
            data: {},
            headers: {'Content-Range': 'bytes */$totalSize'},
          );
        }

        return ScanApiResponse(
          statusCode: 206,
          data: {},
          filePath: streamFile,
          fileStart: start,
          fileEnd: end,
          fileSize: totalSize,
          headers: {
            'Content-Range': 'bytes $start-$end/$totalSize',
            'Accept-Ranges': 'bytes',
            'Content-Length': (end - start + 1).toString(),
            'Content-Type': 'video/mp4',
            'Cache-Control': 'public, max-age=86400, stale-while-revalidate=3600',
            'ETag': etag,
          },
        );
      }
    }

    return ScanApiResponse(
      statusCode: 200,
      data: {},
      filePath: streamFile,
      fileSize: totalSize,
      headers: {
        'Content-Length': totalSize.toString(),
        'Accept-Ranges': 'bytes',
        'Content-Type': 'video/mp4',
        'Cache-Control': 'public, max-age=86400, stale-while-revalidate=3600',
        'ETag': etag,
      },
    );
  }

  // =========================================================================
  // 4. MERGE PIPELINE APPROVE: POST /api/scans/[id]/merge-pipeline/approve
  // =========================================================================

  static Future<ScanApiResponse> approveMergePipeline({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String? sessionToken,
    required String scanId,
    required List<int> minutes,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final pipeline = scan.mergePipeline;
    if (pipeline == null || pipeline.status != 'awaiting_approval' || pipeline.minuteSuggestions.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Minute list ready nahi hai — pehle pipeline complete hone do.'});
    }
    if (SchedulerService.isRunning(scanId)) {
      return ScanApiResponse(statusCode: 409, data: {'error': 'Scan already running'});
    }

    final suggestedSet = pipeline.minuteSuggestions.map((s) => s.minute).toSet();
    final approved = minutes.where((m) => suggestedSet.contains(m)).toList();
    if (approved.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Kam se kam ek suggested minute approve karo.'});
    }

    final applied = applyApprovedMinutes(scan, approved, pipeline.minuteSuggestions);
    if (!applied.ok) {
      return ScanApiResponse(statusCode: 400, data: {'error': applied.error ?? 'Error applying approved minutes'});
    }
    final rangeNotes = applied.rangeNotes ?? [];

    approved.sort();
    pipeline.status = 'approved';
    pipeline.approvedMinutes = approved;
    scan.mergePipeline = pipeline;

    StoreService.addLog(
      scan,
      LogLevel.success,
      'Minute list approved: movie minute(s) ${approved.map((m) => m + 1).join(', ')} — Gemini scan start ho raha hai',
    );
    if (rangeNotes.isNotEmpty) {
      StoreService.addLog(
        scan,
        LogLevel.info,
        'Per-minute movie ranges (Pegasus segment_4 se): ${rangeNotes.join('; ')}',
      );
    }
    await storageService.updateScan(scan);

    // Auto-start Gemini scan
    final userApiKeys = await UserKeysService.getAllUserApiKeys(session.username);
    if (userApiKeys.isEmpty) {
      return ScanApiResponse(
        statusCode: 400,
        data: {'error': 'Approved! Lekin Gemini API key nahi hai — Settings me key add karke Start dabao.'},
      );
    }

    bool charged = false;
    if (session.role != 'admin') {
      final newBalance = await TokenService.deductTokens(session.username, SCAN_TOKEN_COST);
      if (newBalance == null) {
        return ScanApiResponse(
          statusCode: 402,
          data: {
            'error': 'Tokens khatm ho gaye hain! 1 scan = $SCAN_TOKEN_COST tokens. Admin se tokens lo.',
            'tokensExhausted': true,
          },
        );
      }
      charged = true;
    }

    final tlApiKey = await UserKeysService.getUserTwelveLabsKey(session.username);
    final result = await SchedulerService.start(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: userApiKeys,
    );

    if (result['ok'] != true) {
      if (charged) await TokenService.refundTokens(session.username, SCAN_TOKEN_COST);
      return ScanApiResponse(statusCode: 400, data: {'error': result['error'] ?? 'Scan failed to start'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'approved': approved.map((m) => m + 1).toList()});
  }

  // =========================================================================
  // 5. MERGE PIPELINE: GET & POST /api/scans/[id]/merge-pipeline
  // =========================================================================

  static Future<ScanApiResponse> getMergePipeline({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final tlKey = await UserKeysService.getUserTwelveLabsKey(session.username);
    return ScanApiResponse(
      statusCode: 200,
      data: {
        'hasKey': tlKey != null && tlKey.isNotEmpty,
        'ready': MergePipelineService.pipelineReady(scan),
        'running': MergePipelineService.isPipelineRunning(scanId),
        'pipeline': scan.mergePipeline?.toJson() ?? {'status': 'idle'},
        'twelveLabs': scan.twelveLabs?.toJson() ?? {'status': 'none'},
        'prefilter': scan.prefilter?.toJson(),
      },
    );
  }

  static Future<ScanApiResponse> postMergePipeline({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
    String? action,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final tlKey = await UserKeysService.getUserTwelveLabsKey(session.username);
    if (tlKey == null || tlKey.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'TwelveLabs API key set nahi hai — Settings me add karo.'});
    }

    if (!MergePipelineService.pipelineReady(scan)) {
      return ScanApiResponse(
        statusCode: 400,
        data: {'error': 'Short + movie upload aur trim confirm hone ke baad hi pipeline chalti hai.'},
      );
    }

    if (action == 'retry' && scan.mergePipeline != null) {
      scan.mergePipeline!.error = null;
      await storageService.updateScan(scan);
    }

    final result = await MergePipelineService.startMergePipeline(
      storageService: storageService,
      scanId: scanId,
    );

    if (result['ok'] != true) {
      return ScanApiResponse(statusCode: 409, data: {'error': result['error'] ?? 'Pipeline start failed'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'started': true});
  }

  // =========================================================================
  // 6. MINUTE FINDER: GET, POST, DELETE /api/scans/[id]/minute-finder
  // =========================================================================

  static Future<ScanApiResponse> getMinuteFinder({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final mode = await UserKeysService.getUserMinuteFinderMode(session.username);
    final keys = await UserKeysService.getAllUserApiKeys(session.username);

    return ScanApiResponse(
      statusCode: 200,
      data: {
        'mode': mode,
        'keyCount': keys.length,
        'models': ['gemini-3.6-flash', 'gemini-3.7-flash', 'gemini-3.8-flash'],
        'maxShortSec': GeminiMinuteFinderService.MINUTE_FINDER_MAX_SHORT_SEC,
        'ready': GeminiMinuteFinderService.minuteFinderReady(scan),
        'running': GeminiMinuteFinderService.isMinuteFinderRunning(scanId),
        'scanRunning': SchedulerService.isRunning(scanId),
        'prescan': scan.geminiPrescan?.toJson() ?? {
          'status': 'idle',
          'windowLen': 1200,
          'uploads': {},
          'windows': [],
        },
      },
    );
  }

  static Future<ScanApiResponse> postMinuteFinder({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String? sessionToken,
    required String scanId,
    String? action,
    List<int>? windowIndices,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final keys = await UserKeysService.getAllUserApiKeys(session.username);
    if (keys.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Gemini API key nahi hai — Settings me apni key add karo.'});
    }

    final mode = action == 'retry' ? 'retry' : action == 'rerun' ? 'rerun' : 'start';
    final result = await GeminiMinuteFinderService.startGeminiMinuteFinder(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: keys,
      mode: mode,
    );

    if (result['ok'] != true) {
      return ScanApiResponse(statusCode: 409, data: {'error': result['error'] ?? 'Minute finder start failed'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'action': mode});
  }

  static Future<ScanApiResponse> deleteMinuteFinder({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    await GeminiMinuteFinderService.stopGeminiMinuteFinder(storageService, scanId);
    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 7. MISSING SCENE SCAN: GET, POST, DELETE /api/scans/[id]/missing-scene-scan
  // =========================================================================

  static Future<ScanApiResponse> getMissingSceneScan({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final running = MissingSceneScannerService.isMissingSceneScannerRunning(scanId);
    final detectedGaps = MissingSceneScannerService.getDetectedMissingScenes(scan);

    return ScanApiResponse(
      statusCode: 200,
      data: {
        'ok': true,
        'running': running,
        'state': scan.missingSceneScan?.toJson(),
        'detectedGaps': detectedGaps.map((g) => {
          'id': g.id,
          'shortStart': g.shortStart,
          'shortEnd': g.shortEnd,
          'duration': g.duration,
        }).toList(),
      },
    );
  }

  static Future<ScanApiResponse> postMissingSceneScan({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String? sessionToken,
    required String scanId,
    List<Map<String, dynamic>>? scenes,
    List<int>? windowIndices,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final keys = await UserKeysService.getAllUserApiKeys(session.username);
    if (keys.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Gemini API key nahi hai — Settings me apni key add karo.'});
    }

    final sceneList = scenes ?? [];
    if (sceneList.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Kam se kam 1 missing scene select karo.'});
    }

    final targets = sceneList.map((s) => MissingSceneTarget(
      id: s['id']?.toString() ?? 'target-${s["start"]}-${s["end"]}',
      shortStart: (s['start'] as num?)?.toDouble() ?? 0.0,
      shortEnd: (s['end'] as num?)?.toDouble() ?? 0.0,
      duration: ((s['end'] as num?)?.toDouble() ?? 0.0) - ((s['start'] as num?)?.toDouble() ?? 0.0),
    )).toList();

    final result = await MissingSceneScannerService.startMissingSceneScanner(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: keys,
      selectedScenes: targets,
      windowIndices: windowIndices,
    );

    if (result['ok'] != true) {
      return ScanApiResponse(statusCode: 409, data: {'error': result['error'] ?? 'Failed to start missing scene scan'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  static Future<ScanApiResponse> deleteMissingSceneScan({
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    MissingSceneScannerService.stopMissingSceneScanner(scanId);
    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 8. RENDER CANCEL: POST /api/scans/[id]/render/cancel
  // =========================================================================

  static Future<ScanApiResponse> cancelRender({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});

    final isRunning = RenderService.isRenderActive(scanId);
    if (!isRunning) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'No render in progress'});
    }

    RenderService.cancelRender(scanId);
    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 9. RENDER DOWNLOAD: GET /api/scans/[id]/render/download
  // =========================================================================

  static Future<ScanApiResponse> downloadRender({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
    bool asDownload = false,
    String? rangeHeader,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Not found'}, statusText: 'Not found');
    }

    final file = RenderService.renderOutputPath(scanId);
    final f = File(file);
    if (!f.existsSync() || scan.renderJob?.status != 'done') {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Rendered file not found'}, statusText: 'Rendered file not found');
    }

    final baseName = (scan.movieName ?? 'render').replaceAll(RegExp(r'\.[^.]+$'), '');
    final resolution = scan.renderJob?.settings?.resolution ?? 'export';
    final rawFileName = '$baseName-stitched-$resolution.mp4';
    final safeFileName = rawFileName.replaceAll(RegExp(r'[^\w.\- ]+'), '_');

    final headers = <String, String>{};
    if (asDownload) {
      headers['Content-Disposition'] = 'attachment; filename="$safeFileName"';
    }

    final stat = f.statSync();
    final totalSize = stat.size;

    if (rangeHeader != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (m != null) {
        final start = int.parse(m.group(1)!);
        const chunkSize = 4 * 1024 * 1024;
        final end = (m.group(2) != null && m.group(2)!.isNotEmpty)
            ? min(int.parse(m.group(2)!), totalSize - 1)
            : min(start + chunkSize - 1, totalSize - 1);

        if (start >= totalSize) {
          return ScanApiResponse(
            statusCode: 416,
            data: {},
            headers: {'Content-Range': 'bytes */$totalSize'},
          );
        }

        headers.addAll({
          'Content-Range': 'bytes $start-$end/$totalSize',
          'Accept-Ranges': 'bytes',
          'Content-Length': (end - start + 1).toString(),
          'Content-Type': 'video/mp4',
        });

        return ScanApiResponse(
          statusCode: 206,
          data: {},
          filePath: file,
          fileStart: start,
          fileEnd: end,
          fileSize: totalSize,
          headers: headers,
        );
      }
    }

    headers.addAll({
      'Content-Length': totalSize.toString(),
      'Accept-Ranges': 'bytes',
      'Content-Type': 'video/mp4',
    });

    return ScanApiResponse(
      statusCode: 200,
      data: {},
      filePath: file,
      fileSize: totalSize,
      headers: headers,
    );
  }

  // =========================================================================
  // 10. RENDER: POST /api/scans/[id]/render
  // =========================================================================

  static Map<String, dynamic> validateRenderSettings(dynamic input) {
    if (input == null || input is! Map) return {'ok': false, 'error': 'Missing render settings'};
    final s = input as Map<String, dynamic>;
    final res = s['resolution'];
    if (res == null || !['480p', '720p', '1080p', '2k', '4k'].contains(res)) {
      return {'ok': false, 'error': 'Invalid resolution (480p, 720p, 1080p, 2k, 4k)'};
    }
    final fps = s['fps'] is num ? (s['fps'] as num).toInt() : int.tryParse(s['fps']?.toString() ?? '');
    if (fps == null || ![24, 25, 30, 60].contains(fps)) {
      return {'ok': false, 'error': 'Invalid FPS. Choose one of: 24, 25, 30, 60'};
    }
    final vb = s['videoBitrateKbps'] is num ? (s['videoBitrateKbps'] as num).toInt() : int.tryParse(s['videoBitrateKbps']?.toString() ?? '');
    if (vb == null || vb < 250 || vb > 100000) {
      return {'ok': false, 'error': 'Video bitrate must be between 250 and 100000 kbps'};
    }
    final ab = s['audioBitrateKbps'] is num ? (s['audioBitrateKbps'] as num).toInt() : int.tryParse(s['audioBitrateKbps']?.toString() ?? '');
    if (ab == null || ab < 32 || ab > 320) {
      return {'ok': false, 'error': 'Audio bitrate must be between 32 and 320 kbps'};
    }
    final headPad = (s['headPaddingSec'] as num?)?.toDouble() ?? 0.0;
    final headPaddingSec = headPad > 0 ? min(60.0, headPad.roundToDouble()) : 0.0;
    final tailPad = (s['tailPaddingSec'] as num?)?.toDouble() ?? 0.0;
    final tailPaddingSec = tailPad > 0 ? min(60.0, tailPad.roundToDouble()) : 0.0;

    return {
      'ok': true,
      'settings': RenderSettings(
        resolution: res,
        fps: fps,
        videoBitrateKbps: vb,
        audioBitrateKbps: ab,
        headPaddingSec: headPaddingSec,
        tailPaddingSec: tailPaddingSec,
      ),
    };
  }

  static Future<ScanApiResponse> startRender({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required String? sessionToken,
    required String scanId,
    required Map<String, dynamic> body,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (scan.status != ScanStatus.done && scan.status != ScanStatus.stopped) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Scan must be complete or stopped before rendering'});
    }

    final segments = RenderSegmentsUtils.buildRenderSegments(scan.matches);
    if (segments.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'No matched scenes to render'});
    }

    final v = validateRenderSettings(body);
    if (v['ok'] != true) {
      return ScanApiResponse(statusCode: 400, data: {'error': v['error']});
    }

    final settings = v['settings'] as RenderSettings;
    final res = await RenderService.startRender(
      storageService: storageService,
      ffmpegService: ffmpegService,
      scanId: scanId,
      settings: settings,
    );

    if (res['ok'] != true) {
      return ScanApiResponse(statusCode: 409, data: {'error': res['error'] ?? 'Render start failed'});
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // BATCH VERIFY: GET & POST /api/scans/[id]/batch-verify
  // =========================================================================

  static Future<ScanApiResponse> getBatchVerify({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    final state = BatchVerifierService.getOrCreateBatchVerifyState(scan);
    return ScanApiResponse(
      statusCode: 200,
      data: {
        'batchVerify': state,
        'matchCount': scan.matches.length,
        'shortDuration': scan.shortDuration ?? 0.0,
      },
    );
  }

  static Future<ScanApiResponse> postBatchVerify({
    required StorageService storageService,
    required BatchVerifierService batchVerifierService,
    required String? sessionToken,
    required String scanId,
    String? action,
    int? minuteIndex,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (action == 'stop') {
      batchVerifierService.stopBatchVerification(scanId);
      return ScanApiResponse(statusCode: 200, data: {'ok': true, 'message': 'Batch verification stopped'});
    }

    if (action == 'verify_minute' && minuteIndex != null) {
      batchVerifierService.verifySingleMinute(scanId, minuteIndex);
      return ScanApiResponse(
        statusCode: 200,
        data: {'ok': true, 'message': 'Verification started for minute ${minuteIndex + 1}'},
      );
    }

    batchVerifierService.startBatchVerificationAll(scanId);
    return ScanApiResponse(
      statusCode: 200,
      data: {'ok': true, 'message': 'All-in-one batch verification started'},
    );
  }

  // =========================================================================
  // CANDIDATES PICK: POST /api/scans/[id]/candidates/pick
  // =========================================================================

  static Future<ScanApiResponse> pickCandidate({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
    String? groupId,
    dynamic candidateIndex, // int or null
    bool? viaRescan,
    double? shortStart,
    double? shortEnd,
    double? movieStart,
    double? movieEnd,
    int? chunkIndex,
    String? model,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Not found'});
    }

    if (RenderService.isRenderActive(scanId) || scan.renderJob?.status == 'rendering') {
      return ScanApiResponse(
        statusCode: 409,
        data: {'error': 'Render chal raha hai — finish ya cancel hone ke baad main clip badlo'},
      );
    }

    CandidateGroup? g = scan.candidateGroups.where((x) => x.id == groupId).firstOrNull;
    if (g == null && shortStart != null && shortEnd != null) {
      g = scan.candidateGroups.where((x) => CandidatePickUtils.sameShortSegment(x.shortStart, x.shortEnd, shortStart, shortEnd)).firstOrNull;
    }
    if (g == null) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Candidate group not found'});
    }

    if (candidateIndex == null) {
      g.userPick = null;
      CandidatePickUtils.applyGroupMatches(scan, g);
      StoreService.addLog(
        scan,
        LogLevel.info,
        'User choice cleared for short ${fmtTime(g.shortStart)}–${fmtTime(g.shortEnd)} — AI verdict (${g.status}) restored',
      );
    } else {
      int idx = (candidateIndex as num).toInt();
      if (idx < 0 || idx >= g.candidates.length) {
        if (movieStart != null && movieEnd != null) {
          final found = g.candidates.indexWhere(
            (c) => (c.movieStart - movieStart).abs() < 0.5 && (c.movieEnd - movieEnd).abs() < 0.5,
          );
          if (found >= 0) {
            idx = found;
          } else {
            idx = g.candidates.length;
            g.candidates.add(CandidateEntry(
              id: 'cand-${chunkIndex ?? 0}-$idx',
              shortStart: shortStart ?? g.shortStart,
              shortEnd: shortEnd ?? g.shortEnd,
              movieStart: movieStart,
              movieEnd: movieEnd,
              chunkIndex: chunkIndex ?? 0,
              model: model ?? 'gemini-3.7-flash',
              verdict: 'same',
              rescanStatus: 'none',
            ));
          }
        } else {
          return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid candidate index'});
        }
      }

      final c = g.candidates[idx];
      final isViaRescan = viaRescan == true;
      if (isViaRescan && (c.rescanMovieStart == null || c.rescanMovieEnd == null)) {
        return ScanApiResponse(statusCode: 400, data: {'error': 'This candidate has no rescan window'});
      }

      g.userPick = UserPick(index: idx, viaRescan: isViaRescan, at: DateTime.now().millisecondsSinceEpoch);
      CandidatePickUtils.applyGroupMatches(scan, g);

      final ms = isViaRescan ? c.rescanMovieStart! : c.movieStart;
      final me = isViaRescan ? c.rescanMovieEnd! : c.movieEnd;

      StoreService.addLog(
        scan,
        LogLevel.success,
        'USER CHOICE: short ${fmtTime(g.shortStart)}–${fmtTime(g.shortEnd)} → movie ${fmtTime(ms)}–${fmtTime(me)} (candidate #${idx + 1}${isViaRescan ? ', rescan window' : ''}, chunk ${c.chunkIndex}) set as MAIN clip — AI verdict was ${g.status}. Preview + export input updated.',
      );
    }

    if (scan.report != null) {
      scan.report!.matches = scan.matches;
    }

    await storageService.updateScan(scan);
    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'matches': scan.matches.length});
  }

  // =========================================================================
  // PRIVATE HELPERS FOR GROUP 7
  // =========================================================================

  static String _fmtDur(double sec) {
    final s = sec.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return h > 0 ? '${h}h ${m}m ${ss}s' : '${m}m ${ss}s';
  }

  static String _maskKey(String key) {
    if (key.length <= 10) return '***';
    return '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
  }

  static String _generateScanId() {
    final rand = Random();
    final values = List<int>.generate(8, (i) => rand.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<void> _afterMediaReady({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    String? username,
  }) async {
    try {
      final scans = await storageService.loadScans();
      final fresh = scans.where((s) => s.id == scanId).firstOrNull;
      if (fresh != null && MergePipelineService.pipelineReady(fresh)) {
        final uname = username ?? fresh.ownerUsername ?? 'admin';
        final mode = await UserKeysService.getUserMinuteFinderMode(uname);
        if (mode == 'gemini') {
          final keys = await UserKeysService.getAllUserApiKeys(uname);
          if (keys.isNotEmpty) {
            GeminiMinuteFinderService.startGeminiMinuteFinder(
              storageService: storageService,
              ffmpegService: ffmpegService,
              geminiService: geminiService,
              scanId: scanId,
              apiKeys: keys,
            );
          }
        } else if (mode == 'twelvelabs') {
          MergePipelineService.startMergePipeline(
            storageService: storageService,
            scanId: scanId,
          );
        }
      }
    } catch (_) {}
  }

  // =========================================================================
  // 13. RESCAN SCENE: POST /api/scans/[id]/rescan-scene
  // =========================================================================

  static Future<ScanApiResponse> rescanScene({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required SessionUser? session,
    required String scanId,
    required double shortStart,
    required double shortEnd,
    required double movieRangeStart,
    required double movieRangeEnd,
    String? model,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (shortEnd <= shortStart) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid short video timestamps'});
    }
    if (movieRangeEnd <= movieRangeStart) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid movie search range'});
    }
    if ((movieRangeEnd - movieRangeStart) > 180) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Movie search range cannot exceed 3 minutes (180s)'});
    }

    if (scan.shortPath == null || scan.moviePath == null) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Source media missing for this scan'});
    }

    final userKeys = await UserKeysService.getAllUserApiKeys(session.username);
    if (userKeys.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'No Gemini API keys configured. Please add an API key in Settings.'});
    }

    final chosenModel = (model != null && model.isNotEmpty) ? model : AppConstants.defaultRescanModel;

    final tempDir = Directory(p.join(Directory.systemTemp.path, 'rescan_${scanId}_${DateTime.now().millisecondsSinceEpoch}'));
    if (!await tempDir.exists()) await tempDir.create(recursive: true);

    final targetSegmentPath = p.join(tempDir.path, 'target_segment.mp4');
    final chunkMoviePath = p.join(tempDir.path, 'search_window.mp4');

    try {
      await ffmpegService.extractClip(
        sourcePath: scan.shortPath!,
        start: shortStart,
        end: shortEnd,
        outputPath: targetSegmentPath,
      );

      await ffmpegService.extractClip(
        sourcePath: scan.moviePath!,
        start: movieRangeStart,
        end: movieRangeEnd,
        outputPath: chunkMoviePath,
      );

      geminiService.configure(userKeys.first, modelName: chosenModel);
      final rescanRes = await geminiService.rescanSegment(
        targetSegmentPath: targetSegmentPath,
        chunkMoviePath: chunkMoviePath,
        chunkOffsetSeconds: movieRangeStart,
        rescanModel: chosenModel,
      );

      if (rescanRes.matchFound) {
        final newMovieStart = rescanRes.movieStart;
        final newMovieEnd = rescanRes.movieEnd;
        final chIdx = (newMovieStart / 60.0).floor();
        final ts = DateTime.now().millisecondsSinceEpoch;

        CandidateGroup? g = scan.candidateGroups.where(
          (grp) => CandidatePickUtils.sameShortSegment(grp.shortStart, grp.shortEnd, shortStart, shortEnd)
        ).firstOrNull;

        if (g == null) {
          g = CandidateGroup(
            id: 'cg-rescan-$ts-${Random().nextInt(1000)}',
            shortStart: shortStart,
            shortEnd: shortEnd,
            candidates: [],
            status: 'confirmed',
            confirmedIndex: 0,
            confirmedViaRescan: true,
            attempts: 1,
            origin: 'rescan',
          );
          scan.candidateGroups.add(g);
        }

        final prevMatch = scan.matches.where(
          (m) => CandidatePickUtils.sameShortSegment(m.shortStart, m.shortEnd, shortStart, shortEnd)
        ).firstOrNull;

        if (prevMatch != null) {
          final alreadyIn = g.candidates.any(
            (c) => (c.movieStart - prevMatch.movieStart).abs() < 0.5 && (c.movieEnd - prevMatch.movieEnd).abs() < 0.5
          );
          if (!alreadyIn) {
            g.candidates.add(CandidateEntry(
              id: 'cand-${prevMatch.chunkIndex ?? 0}-$ts',
              chunkIndex: prevMatch.chunkIndex ?? chIdx,
              movieStart: prevMatch.movieStart,
              movieEnd: prevMatch.movieEnd,
              confidence: 0.9,
              verifyReason: prevMatch.reason ?? 'Previous match',
              model: prevMatch.model ?? chosenModel,
              verified: prevMatch.verified ?? false,
              verdict: prevMatch.verified == true ? 'same' : 'different',
            ));
          }
        }

        final newCandIndex = g.candidates.length;
        g.candidates.add(CandidateEntry(
          id: 'cand-rescan-$chIdx-$ts',
          chunkIndex: chIdx,
          movieStart: newMovieStart,
          movieEnd: newMovieEnd,
          confidence: 0.99,
          verifyReason: 'Targeted Rescan ($chosenModel)',
          model: chosenModel,
          verdict: 'same',
          rescanStatus: 'found',
          rescanMovieStart: newMovieStart,
          rescanMovieEnd: newMovieEnd,
          reason: 'Found via targeted rescan on $chosenModel (User Review)',
        ));

        g.status = 'confirmed';
        g.confirmedIndex = newCandIndex;
        g.confirmedViaRescan = true;
        g.userPick = UserPick(index: newCandIndex, viaRescan: true, at: ts);

        scan.matches.removeWhere((m) => CandidatePickUtils.sameShortSegment(m.shortStart, m.shortEnd, shortStart, shortEnd));
        final newMatch = ChunkMatch(
          id: 'match-rescan-$ts',
          shortStart: shortStart,
          shortEnd: shortEnd,
          movieStart: newMovieStart,
          movieEnd: newMovieEnd,
          chunkIndex: chIdx,
          model: chosenModel,
          verified: true,
          viaRescan: true,
          userPick: true,
          origin: 'rescan',
          originWindow: g.originWindow,
          reason: 'Rescanned via Retry ($chosenModel) — User Review',
        );
        scan.matches.add(newMatch);
        scan.matches.sort((a, b) => a.shortStart.compareTo(b.shortStart));

        if (scan.report != null) {
          scan.report!.matches = scan.matches;
        }

        StoreService.addLog(
          scan,
          LogLevel.success,
          'Rescan match found: short ${_fmtDur(shortStart)}–${_fmtDur(shortEnd)} → movie ${_fmtDur(newMovieStart)}–${_fmtDur(newMovieEnd)} using $chosenModel',
        );

        await storageService.updateScan(scan);
        return ScanApiResponse(statusCode: 200, data: {
          'found': true,
          'movieStart': newMovieStart,
          'movieEnd': newMovieEnd,
          'model': chosenModel,
          'message': 'Match found and applied as main clip',
        });
      } else {
        StoreService.addLog(
          scan,
          LogLevel.info,
          'Rescan: no match found in range ${_fmtDur(movieRangeStart)}–${_fmtDur(movieRangeEnd)} using $chosenModel',
        );
        return ScanApiResponse(statusCode: 200, data: {
          'found': false,
          'message': 'No match found in the specified range.',
        });
      }
    } catch (e) {
      return ScanApiResponse(statusCode: 500, data: {'error': 'Rescan failed: $e'});
    } finally {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  // =========================================================================
  // 14. GET SCAN: GET /api/scans/[id]
  // =========================================================================

  static Future<ScanApiResponse> getScan({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
    bool probeMedia = false,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (probeMedia) {
      try {
        await MediaService.probeMediaStatus(scan);
      } catch (_) {}
    }

    return ScanApiResponse(statusCode: 200, data: scan.toJson());
  }

  // =========================================================================
  // 15. DELETE SCAN: DELETE /api/scans/[id]
  // =========================================================================

  static Future<ScanApiResponse> deleteScan({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    SchedulerService.stop(scanId);
    GeminiMinuteFinderService.stopGeminiMinuteFinder(scanId);
    RenderService.cancelRender(scanId);
    MissingSceneScannerService.stopMissingSceneScan(scanId);
    await BackgroundQueueService.stopBackgroundScan(storageService: storageService, scanId: scanId);

    await MediaService.deleteMediaDir(scanId);
    await storageService.deleteScan(scanId);

    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 16. PATCH SCAN: PATCH /api/scans/[id]
  // =========================================================================

  static Future<ScanApiResponse> patchScan({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
    required Map<String, dynamic> body,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (body.containsKey('customName')) {
      scan.customName = (body['customName'] as String?)?.trim();
    }
    if (body.containsKey('autoMode')) {
      scan.autoMode = body['autoMode'] == true;
    }
    if (body.containsKey('verifierEnabled')) {
      scan.verifierEnabled = body['verifierEnabled'] == true;
    }
    if (body.containsKey('selectedModel')) {
      scan.selectedModel = body['selectedModel'] as String?;
    }

    await storageService.updateScan(scan);
    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'scan': scan.toJson()});
  }

  // =========================================================================
  // 17. SEGMENTS: POST /api/scans/[id]/segments
  // =========================================================================

  static Future<ScanApiResponse> updateSegments({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
    required List<dynamic> segments,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (segments.isEmpty) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Segments list is required'});
    }

    scan.shortSegments = segments
        .map((s) => ShortSegmentState.fromJson(s as Map<String, dynamic>))
        .toList();

    StoreService.addLog(scan, LogLevel.info, 'Updated ${segments.length} short segments');
    await storageService.updateScan(scan);

    return ScanApiResponse(statusCode: 200, data: {
      'ok': true,
      'segments': scan.shortSegments.map((s) => s.toJson()).toList(),
    });
  }

  // =========================================================================
  // 18. START SCAN: POST /api/scans/[id]/start
  // =========================================================================

  static Future<ScanApiResponse> startScan({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required SessionUser? session,
    required String scanId,
    bool background = false,
    bool resume = false,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (scan.status == ScanStatus.scanning) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Scan is already running'});
    }

    if (session.role != 'admin') {
      final balance = await TokenService.getTokenBalance(session.username);
      if (balance < SCAN_TOKEN_COST) {
        return ScanApiResponse(statusCode: 402, data: {
          'error': 'Insufficient tokens ($balance available, $SCAN_TOKEN_COST required). Contact admin for tokens.'
        });
      }
      final newBalance = await TokenService.deductTokens(session.username, SCAN_TOKEN_COST);
      if (newBalance == null) {
        return ScanApiResponse(statusCode: 402, data: {'error': 'Failed to deduct tokens'});
      }
    }

    if (background) {
      await BackgroundQueueService.enqueueBackgroundScan(
        storageService: storageService,
        scanId: scanId,
        username: session.username,
        resume: resume,
      );
      return ScanApiResponse(statusCode: 200, data: {
        'ok': true,
        'background': true,
        'message': 'Scan enqueued in background queue',
      });
    } else {
      scan.status = ScanStatus.scanning;
      scan.startedAt = DateTime.now();
      scan.error = null;
      await storageService.updateScan(scan);

      SchedulerService.startScan(
        storageService: storageService,
        ffmpegService: ffmpegService,
        geminiService: geminiService,
        scan: scan,
      );

      return ScanApiResponse(statusCode: 200, data: {'ok': true, 'scan': scan.toJson()});
    }
  }

  // =========================================================================
  // 19. STOP SCAN: POST /api/scans/[id]/stop
  // =========================================================================

  static Future<ScanApiResponse> stopScan({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    SchedulerService.stop(scanId);
    GeminiMinuteFinderService.stopGeminiMinuteFinder(scanId);
    MissingSceneScannerService.stopMissingSceneScan(scanId);
    await BackgroundQueueService.stopBackgroundScan(storageService: storageService, scanId: scanId);

    scan.status = ScanStatus.stopped;
    StoreService.addLog(scan, LogLevel.warning, 'Scan stopped by user');
    await storageService.updateScan(scan);

    return ScanApiResponse(statusCode: 200, data: {'ok': true});
  }

  // =========================================================================
  // 20. TRIM MOVIE: POST /api/scans/[id]/trim
  // =========================================================================

  static Future<ScanApiResponse> trimMovie({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required SessionUser? session,
    required String scanId,
    required double start,
    double? end,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (start < 0) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Trim start cannot be negative'});
    }
    if (end != null && end <= start) {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Trim end must be greater than trim start'});
    }

    scan.movieTrimStart = start;
    scan.movieTrimEnd = end;
    scan.awaitingTrim = false;

    StoreService.addLog(
      scan,
      LogLevel.info,
      'Movie trimmed: ${_fmtDur(start)} to ${end != null ? _fmtDur(end) : 'end'}',
    );

    await storageService.updateScan(scan);

    await _afterMediaReady(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      username: session.username,
    );

    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'scan': scan.toJson()});
  }

  // =========================================================================
  // 21. TWELVELABS: GET & POST /api/scans/[id]/twelvelabs
  // =========================================================================

  static Future<ScanApiResponse> getTwelveLabs({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    final data = await TwelveLabsService.loadEmbeddings(scanId);
    if (data == null) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'TwelveLabs embeddings not found'});
    }

    return ScanApiResponse(statusCode: 200, data: data);
  }

  static Future<ScanApiResponse> twelveLabsGone({
    required SessionUser? session,
    required String scanId,
  }) async {
    return ScanApiResponse(statusCode: 410, data: {
      'error': 'TwelveLabs polling is no longer supported directly on this endpoint. Embeddings are generated during prescan.'
    });
  }

  // =========================================================================
  // 22. UPLOAD: GET (probe) & POST /api/scans/[id]/upload
  // =========================================================================

  static Future<ScanApiResponse> probeUpload({
    required StorageService storageService,
    required SessionUser? session,
    required String scanId,
    required String kind,
    String? name,
    int? size,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (kind != 'short' && kind != 'movie') {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid kind'});
    }

    final reuse = await MediaService.findReusableMedia(
      storageService: storageService,
      kind: kind,
      name: name ?? '',
      size: size ?? 0,
      excludeId: scanId,
    );

    if (reuse != null) {
      return ScanApiResponse(statusCode: 200, data: {
        'reusable': true,
        'sourceScanId': reuse.scanId,
        'name': reuse.name,
        'size': reuse.size,
      });
    }

    return ScanApiResponse(statusCode: 200, data: {'reusable': false});
  }

  static Future<ScanApiResponse> uploadStreamOrReuse({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required SessionUser? session,
    required String scanId,
    required String kind,
    String? name,
    bool reuse = false,
    String? reuseSourceScanId,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final scan = await storageService.getScan(scanId);
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (kind != 'short' && kind != 'movie') {
      return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid kind: must be short or movie'});
    }

    if (reuse && reuseSourceScanId != null && reuseSourceScanId.isNotEmpty) {
      final res = await MediaService.reuseMedia(
        storageService: storageService,
        ffmpegService: ffmpegService,
        targetScan: scan,
        kind: kind,
        sourceScanId: reuseSourceScanId,
      );

      if (res['ok'] != true) {
        return ScanApiResponse(statusCode: 400, data: res);
      }

      await _afterMediaReady(
        storageService: storageService,
        ffmpegService: ffmpegService,
        geminiService: geminiService,
        scanId: scanId,
        username: session.username,
      );

      return ScanApiResponse(statusCode: 200, data: res);
    } else {
      final res = await MediaService.finalizeUploadedMedia(
        scan,
        kind,
        name ?? (kind == 'short' ? 'short.mp4' : 'movie.mp4'),
        ffmpegService: ffmpegService,
      );

      if (res['ok'] != true) {
        return ScanApiResponse(statusCode: 400, data: res);
      }

      await storageService.updateScan(scan);

      await _afterMediaReady(
        storageService: storageService,
        ffmpegService: ffmpegService,
        geminiService: geminiService,
        scanId: scanId,
        username: session.username,
      );

      return ScanApiResponse(statusCode: 200, data: res);
    }
  }

  // =========================================================================
  // 23. SCANS ROOT: GET (list), POST (create), DELETE (all) /api/scans
  // =========================================================================

  static Future<ScanApiResponse> listScans({
    required StorageService storageService,
    required SessionUser? session,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    var scans = await storageService.loadScans();
    if (session.role != 'admin') {
      scans = scans.where((s) => s.ownerUsername == session.username).toList();
    }

    scans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ScanApiResponse(
      statusCode: 200,
      data: scans.map((s) => s.toJson()).toList(),
    );
  }

  static Future<ScanApiResponse> createScan({
    required StorageService storageService,
    required SessionUser? session,
    Map<String, dynamic> body = const {},
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final id = _generateScanId();
    final customName = (body['customName'] as String?)?.trim();
    final selectedModel = body['selectedModel'] as String?;
    final autoMode = body['autoMode'] as bool? ?? true;
    final verifierEnabled = body['verifierEnabled'] as bool? ?? true;
    final minuteFinderMode = body['minuteFinderMode'] as String? ?? 'gemini';

    final scan = Scan(
      id: id,
      createdAt: DateTime.now(),
      status: ScanStatus.created,
      customName: (customName != null && customName.isNotEmpty) ? customName : null,
      ownerUsername: session.username,
      selectedModel: selectedModel,
      autoMode: autoMode,
      verifierEnabled: verifierEnabled,
      minuteFinderMode: minuteFinderMode,
    );

    await storageService.createScan(scan);
    return ScanApiResponse(statusCode: 201, data: scan.toJson());
  }

  static Future<ScanApiResponse> deleteAllScans({
    required StorageService storageService,
    required SessionUser? session,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }
    if (session.role != 'admin') {
      return ScanApiResponse(statusCode: 403, data: {'error': 'Only admins can delete all scans'});
    }

    final scans = await storageService.loadScans();
    int count = 0;

    for (final scan in scans) {
      SchedulerService.stop(scan.id);
      GeminiMinuteFinderService.stopGeminiMinuteFinder(scan.id);
      RenderService.cancelRender(scan.id);
      MissingSceneScannerService.stopMissingSceneScan(scan.id);
      await BackgroundQueueService.stopBackgroundScan(storageService: storageService, scanId: scan.id);
      await MediaService.deleteMediaDir(scan.id);
      await storageService.deleteScan(scan.id);
      count++;
    }

    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'deleted': count});
  }

  // =========================================================================
  // 24. SETTINGS: GET, PUT, POST /api/settings
  // =========================================================================

  static Future<ScanApiResponse> getSettings({
    required SessionUser? session,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final username = session.username;
    final keys = await UserKeysService.getAllUserApiKeys(username);
    final tlKey = await UserKeysService.getUserTwelveLabsKey(username);
    final minuteFinderMode = await UserKeysService.getUserMinuteFinderMode(username);
    final verifierEnabled = await UserKeysService.getUserVerifierEnabled(username);
    final autoMode = await UserKeysService.getUserAutoMode(username);
    final tokenBalance = await TokenService.getTokenBalance(username);
    final storageUsage = await MediaService.getStorageUsage();

    return ScanApiResponse(statusCode: 200, data: {
      'username': username,
      'role': session.role,
      'apiKeys': keys.map((k) => {'key': _maskKey(k), 'raw': k}).toList(),
      'twelveLabsKey': tlKey != null ? _maskKey(tlKey) : null,
      'minuteFinderMode': minuteFinderMode,
      'verifierEnabled': verifierEnabled,
      'autoMode': autoMode,
      'tokenBalance': tokenBalance,
      'storageUsage': storageUsage,
    });
  }

  static Future<ScanApiResponse> putSettings({
    required SessionUser? session,
    required Map<String, dynamic> body,
  }) async {
    if (session == null) {
      return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});
    }

    final username = session.username;

    if (body.containsKey('apiKeys')) {
      final list = body['apiKeys'] as List<dynamic>? ?? [];
      for (int i = 0; i < MAX_API_KEYS; i++) {
        if (i < list.length && list[i] != null && list[i].toString().trim().isNotEmpty) {
          await UserKeysService.setUserKeyN(username, i + 1, list[i].toString().trim());
        } else {
          await UserKeysService.clearUserKeyN(username, i + 1);
        }
      }
    }

    if (body.containsKey('twelveLabsKey')) {
      final tl = body['twelveLabsKey'] as String?;
      if (tl != null && tl.trim().isNotEmpty) {
        await UserKeysService.setUserTwelveLabsKey(username, tl.trim());
      } else {
        await UserKeysService.clearUserTwelveLabsKey(username);
      }
    }

    if (body.containsKey('minuteFinderMode')) {
      await UserKeysService.setUserMinuteFinderMode(username, body['minuteFinderMode'].toString());
    }

    if (body.containsKey('verifierEnabled')) {
      await UserKeysService.setUserVerifierEnabled(username, body['verifierEnabled'] == true);
    }

    if (body.containsKey('autoMode')) {
      await UserKeysService.setUserAutoMode(username, body['autoMode'] == true);
    }

    return getSettings(session: session);
  }

  static Future<ScanApiResponse> postSettings({
    required SessionUser? session,
    required Map<String, dynamic> body,
  }) async {
    return putSettings(session: session, body: body);
  }
}

