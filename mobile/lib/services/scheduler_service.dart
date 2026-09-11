import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../models/chunk.dart';
import 'storage_service.dart';
import 'media_service.dart';
import 'ffmpeg_service.dart';
import 'gemini_service.dart';
import 'global_gemini_coordinator.dart';
import '../utils/gemini_prompts.dart';
import '../utils/segment_range.dart';
import '../utils/candidate_pick.dart';

/// 1:1 Port of lib/scheduler.ts
/// Core Parallel Chunk Mapping & Verification Scheduler.

class SchedulerService {
  static final Map<String, bool> _activeJobs = {};

  static bool isRunning(String scanId) => _activeJobs[scanId] == true;

  static void stop(String scanId) {
    _activeJobs[scanId] = false;
  }

  /// Start AI chunk scan
  static Future<Map<String, dynamic>> start({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    bool isResume = false,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};
    if (_activeJobs[scanId] == true) return {'ok': false, 'error': 'Scan already running'};
    if (apiKeys.isEmpty) return {'ok': false, 'error': 'No API keys provided'};

    _activeJobs[scanId] = true;
    scan.status = ScanStatus.scanning;
    scan.startedAt ??= DateTime.now().millisecondsSinceEpoch;
    await storageService.updateScan(scan);

    // Run in background
    _runSchedulerAsync(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: apiKeys,
    ).then((_) {
      _activeJobs.remove(scanId);
    }).catchError((err) async {
      _activeJobs.remove(scanId);
      final s = (await storageService.loadScans()).where((x) => x.id == scanId).firstOrNull;
      if (s != null) {
        s.status = ScanStatus.error;
        s.error = err.toString();
        await storageService.updateScan(s);
      }
    });

    return {'ok': true};
  }

  static Future<void> _runSchedulerAsync({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return;

    final mediaDir = MediaService.scanMediaDir(scanId);
    final chunksDir = p.join(mediaDir, 'chunks');

    // Chunks to process
    final pendingChunks = scan.chunks.where((c) => c.status != ChunkStatus.done && c.status != ChunkStatus.error).toList();
    final coordinator = GlobalGeminiCoordinator.instance;
    final modelPool = ['gemini-3.6-flash', 'gemini-3.7-flash', 'gemini-3.8-flash'];

    for (final chunk in pendingChunks) {
      if (_activeJobs[scanId] == false) return;
      chunk.status = ChunkStatus.scanning;
      await storageService.updateScan(scan);

      final chunkFile = p.join(chunksDir, 'chunk-${chunk.index.toString().padLeft(4, '0')}.mp4');
      final shortFile = await MediaService.ensureLocalMedia(scanId, 'short');

      if (!File(chunkFile).existsSync() || shortFile == null || !File(shortFile).existsSync()) {
        chunk.status = ChunkStatus.error;
        chunk.error = 'Chunk/short file missing';
        await storageService.updateScan(scan);
        continue;
      }

      final candidateLanes = <CandidateLane>[];
      for (int i = 0; i < apiKeys.length; i++) {
        for (final m in modelPool) {
          candidateLanes.add(CandidateLane(apiKey: apiKeys[i], keyIdx: i + 1, modelId: m));
        }
      }

      final laneAcquired = await coordinator.acquireFirstAvailableLane(
        scanId: scanId,
        scanTitle: scan.shortName ?? scanId,
        candidates: candidateLanes,
        operation: 'Chunk #${chunk.index}',
        videoSeconds: 60.0,
        isStopping: () => _activeJobs[scanId] == false,
      );

      final CandidateLane selected = laneAcquired['selected'] as CandidateLane;
      final Function releaseLane = laneAcquired['release'] as Function;

      try {
        final shortUp = await geminiService.uploadVideo(apiKey: selected.apiKey, filePath: shortFile);
        final chunkUp = await geminiService.uploadVideo(apiKey: selected.apiKey, filePath: chunkFile);

        final prompt = CHUNK_MAP_PROMPT;
        final resp = await geminiService.generateContent(
          apiKey: selected.apiKey,
          model: selected.modelId,
          parts: [
            {'fileData': {'fileUri': shortUp['uri'], 'mimeType': 'video/mp4'}},
            {'fileData': {'fileUri': chunkUp['uri'], 'mimeType': 'video/mp4'}},
            {'text': prompt},
          ],
        );

        final parsed = parseChunkMatches(resp['text'] ?? '', chunk.index * 60.0);
        chunk.status = ChunkStatus.done;
        chunk.model = selected.modelId;

        if (parsed.isNotEmpty) {
          for (final m in parsed) {
            scan.matches.add(ScanMatch(
              shortStart: m['shortStart'] ?? 0.0,
              shortEnd: m['shortEnd'] ?? 0.0,
              movieStart: m['movieStart'] ?? 0.0,
              movieEnd: m['movieEnd'] ?? 0.0,
              confidence: m['confidence'] ?? 0.9,
              verified: null,
            ));
          }
        }
      } catch (err) {
        chunk.status = ChunkStatus.error;
        chunk.error = err.toString();
        coordinator.reportRateLimit(selected.apiKey, selected.modelId);
      } finally {
        releaseLane();
      }

      await storageService.updateScan(scan);
    }

    if (_activeJobs[scanId] == false) return;

    scan.status = ScanStatus.done;
    scan.finishedAt = DateTime.now().millisecondsSinceEpoch;
    await storageService.updateScan(scan);
  }
}
