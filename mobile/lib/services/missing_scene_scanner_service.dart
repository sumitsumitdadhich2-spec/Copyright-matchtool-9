import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import 'storage_service.dart';
import 'media_service.dart';
import 'ffmpeg_service.dart';
import 'gemini_service.dart';
import 'global_gemini_coordinator.dart';
import '../utils/gemini_prompts.dart';

/// 1:1 Port of lib/missing-scene-scanner.ts
/// Targeted Missing Scene Finder: cuts missing gaps into clips, searches 20-min windows, and verifies candidate matches.

class MissingSceneTarget {
  final String id;
  final double shortStart;
  final double shortEnd;
  final double duration;
  double? clipStart;
  double? clipEnd;

  MissingSceneTarget({
    required this.id,
    required this.shortStart,
    required this.shortEnd,
    required this.duration,
    this.clipStart,
    this.clipEnd,
  });
}

class MissingSceneCandidate {
  final String candidateId;
  final String targetSceneId;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final double confidence;
  final String evidence;
  final String? model;

  MissingSceneCandidate({
    required this.candidateId,
    required this.targetSceneId,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.confidence,
    required this.evidence,
    this.model,
  });
}

class MissingSceneScannerService {
  static final Map<String, bool> _activeControllers = {};

  static bool isMissingSceneScannerRunning(String scanId) => _activeControllers[scanId] == true;

  static void stopMissingSceneScanner(String scanId) {
    _activeControllers[scanId] = false;
  }

  /// Compute gaps in short video based on existing confirmed/verified matches
  static List<MissingSceneTarget> getDetectedMissingScenes(Scan scan) {
    final shortDur = scan.shortDuration ?? 0.0;
    if (shortDur <= 0) return [];

    final activeMatches = (scan.matches)
        .where((m) => m.rejected != true && m.batchVerified != 'rejected')
        .map((m) => {'start': m.shortStart, 'end': m.shortEnd})
        .toList();

    activeMatches.sort((a, b) => a['start']!.compareTo(b['start']!));

    // Merge overlapping
    final merged = <Map<String, double>>[];
    for (final r in activeMatches) {
      if (merged.isEmpty) {
        merged.add(Map<String, double>.from(r));
      } else {
        final last = merged.last;
        if (r['start']! <= last['end']!) {
          if (r['end']! > last['end']!) last['end'] = r['end']!;
        } else {
          merged.add(Map<String, double>.from(r));
        }
      }
    }

    // Invert to get gaps
    final gaps = <Map<String, double>>[];
    double cur = 0.0;
    for (final m in merged) {
      if (m['start']! > cur + 0.4) {
        gaps.add({'start': cur, 'end': m['start']!});
      }
      cur = [cur, m['end']!].reduce((a, b) => a > b ? a : b);
    }
    if (cur + 0.4 < shortDur) {
      gaps.add({'start': cur, 'end': shortDur});
    }

    return gaps.asMap().entries.map((e) {
      final idx = e.key;
      final g = e.value;
      return MissingSceneTarget(
        id: 'gap-${idx + 1}-${g["start"]!.round()}-${g["end"]!.round()}',
        shortStart: double.parse(g['start']!.toStringAsFixed(3)),
        shortEnd: double.parse(g['end']!.toStringAsFixed(3)),
        duration: double.parse((g['end']! - g['start']!).toStringAsFixed(3)),
      );
    }).toList();
  }

  /// Start the missing scene scanner
  static Future<Map<String, dynamic>> startMissingSceneScanner({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    required List<MissingSceneTarget> selectedScenes,
    List<int>? windowIndices,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};
    if (_activeControllers[scanId] == true) {
      return {'ok': false, 'error': 'Missing scene scan is already running'};
    }
    if (apiKeys.isEmpty) return {'ok': false, 'error': 'Gemini API key is required'};
    if (selectedScenes.isEmpty) {
      return {'ok': false, 'error': 'Kripya kam se kam 1 missing scene select karein'};
    }

    _activeControllers[scanId] = true;

    // Run in background
    _runAsync(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: apiKeys,
      selectedScenes: selectedScenes,
      windowIndices: windowIndices,
    ).then((_) {
      _activeControllers.remove(scanId);
    }).catchError((err) {
      _activeControllers.remove(scanId);
    });

    return {'ok': true};
  }

  static Future<void> _runAsync({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    required List<MissingSceneTarget> selectedScenes,
    List<int>? windowIndices,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return;

    final mediaDir = MediaService.scanMediaDir(scanId);
    final shortFile = await MediaService.ensureLocalMedia(scanId, 'short');
    final movieFile = await MediaService.ensureLocalMedia(scanId, 'movie');

    if (shortFile == null || movieFile == null) return;

    final clipOutFile = p.join(mediaDir, 'missing-scene-clip-${DateTime.now().millisecondsSinceEpoch}.mp4');

    if (selectedScenes.length == 1) {
      final t = selectedScenes[0];
      await ffmpegService.extractClipPrecise(
        sourceFile: shortFile,
        startSec: t.shortStart,
        endSec: t.shortEnd,
        outFile: clipOutFile,
      );
      t.clipStart = 0;
      t.clipEnd = t.duration;
    } else {
      await ffmpegService.buildBackupClip(
        sourceFile: shortFile,
        ranges: selectedScenes.map((s) => {'start': s.shortStart, 'end': s.shortEnd}).toList(),
        outFile: clipOutFile,
      );
    }

    // Upload missing scene clip to Gemini
    final up = await geminiService.uploadVideo(apiKey: apiKeys[0], filePath: clipOutFile);
    final clipUri = up['uri'] ?? '';

    // Verify against 20-min windows
    final trimStart = scan.movieTrimStart ?? 0.0;
    final trimEnd = scan.movieTrimEnd ?? scan.movieDuration ?? 0.0;
    final copyDuration = (trimEnd - trimStart).clamp(1.0, 999999.0);

    final prescanMovie = p.join(mediaDir, 'prescan-movie.mp4');
    String movieUri = '';
    if (scan.prescanUploads.isNotEmpty) {
      movieUri = scan.prescanUploads.first.movieUri;
    } else if (File(prescanMovie).existsSync()) {
      final mUp = await geminiService.uploadVideo(apiKey: apiKeys[0], filePath: prescanMovie);
      movieUri = mUp['uri'] ?? '';
    }

    if (movieUri.isEmpty || clipUri.isEmpty) return;

    // Scan windows
    const winLen = 1200.0;
    for (double t = 0.0; t < copyDuration - 0.5; t += winLen) {
      if (_activeControllers[scanId] == false) return;
      final wStart = t;
      final wEnd = [t + winLen, copyDuration].reduce((a, b) => a < b ? a : b);

      final prompt = buildMinuteFinderPrompt(wStart, wEnd);
      try {
        final resp = await geminiService.generateContent(
          apiKey: apiKeys[0],
          model: 'gemini-3.6-flash',
          parts: [
            {'fileData': {'fileUri': clipUri, 'mimeType': 'video/mp4'}, 'videoMetadata': {'fps': 10}},
            {'fileData': {'fileUri': movieUri, 'mimeType': 'video/mp4'}, 'videoMetadata': {'startOffset': '${wStart.toInt()}s', 'endOffset': '${wEnd.toInt()}s'}},
            {'text': prompt},
          ],
        );

        final parsed = parseMinuteFinderOutput(resp['text'] ?? '', wStart, wEnd, true);
        if (parsed.hits.isNotEmpty) {
          // Add candidate matches to scan
          for (final h in parsed.hits) {
            final movieAbsStart = trimStart + h.fileStart;
            final movieAbsEnd = trimStart + h.fileEnd;
            final chunkIdx = (movieAbsStart / 60.0).floor();

            scan.gapBackupCandidates.add(CandidateGroup(
              groupId: 'missing-${DateTime.now().millisecondsSinceEpoch}',
              chunkIndex: chunkIdx,
              candidates: [
                CandidateItem(
                  candidateId: 'cand-${DateTime.now().millisecondsSinceEpoch}',
                  shortStart: h.shortStart ?? 0.0,
                  shortEnd: h.shortEnd ?? (h.fileEnd - h.fileStart),
                  movieStart: movieAbsStart,
                  movieEnd: movieAbsEnd,
                  confidence: h.kind == 'match' ? 0.95 : 0.70,
                  evidence: h.evidence,
                )
              ],
            ));
          }
          await storageService.updateScan(scan);
        }
      } catch (_) {}
    }
  }
}
