import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import 'storage_service.dart';
import 'media_service.dart';
import 'ffmpeg_service.dart';
import 'gemini_service.dart';
import 'global_gemini_coordinator.dart';
import '../utils/gemini_prompts.dart';
import '../utils/minute_ranges.dart';

/// 1:1 Port of lib/gemini-minute-finder.ts
/// Gemini Minute Finder orchestration service: 20-min window sweep, backup pass, minute suggestions, and chunk scan auto-dispatch.

class GeminiMinuteFinderService {
  static const double MINUTE_FINDER_WINDOW_SEC = 1200.0;
  static const double MINUTE_FINDER_MAX_SHORT_SEC = 180.0;
  static const int UPLOAD_TTL_MS = 47 * 60 * 60 * 1000;

  static final Map<String, bool> _runningControllers = {};

  static bool isMinuteFinderRunning(String scanId) => _runningControllers[scanId] == true;

  static bool minuteFinderReady(Scan scan) {
    return scan.shortDuration != null && scan.movieDuration != null && scan.awaitingTrim == false;
  }

  static String _fmtDur(double sec) {
    final s = sec.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}m ${ss.toString().padLeft(2, '0')}s' : '${m}m ${ss}s';
  }

  /// Start the minute finder
  static Future<Map<String, dynamic>> startGeminiMinuteFinder({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    String mode = 'start',
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};
    if (!minuteFinderReady(scan)) {
      return {'ok': false, 'error': 'Short + movie upload aur trim confirm hone ke baad hi minute finder chalta hai.'};
    }
    if (_runningControllers[scanId] == true) {
      return {'ok': false, 'error': 'Minute finder already running'};
    }
    if (apiKeys.isEmpty) {
      return {'ok': false, 'error': 'Gemini API key nahi hai — Settings me apni key add karo.'};
    }

    _runningControllers[scanId] = true;
    scan.geminiPrescanStatus = 'preparing';
    scan.geminiPrescanProgress = 'Starting...';
    scan.geminiPrescanError = null;
    await storageService.updateScan(scan);

    // Run in background
    _runAsync(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: apiKeys,
      mode: mode,
    ).then((_) {
      _runningControllers.remove(scanId);
    }).catchError((err) async {
      _runningControllers.remove(scanId);
      final s = (await storageService.loadScans()).where((x) => x.id == scanId).firstOrNull;
      if (s != null) {
        s.geminiPrescanStatus = 'error';
        s.geminiPrescanError = err.toString();
        await storageService.updateScan(s);
      }
    });

    return {'ok': true};
  }

  static Future<void> stopGeminiMinuteFinder(String scanId, [StorageService? storageService]) async {
    _runningControllers[scanId] = false;
    if (storageService != null) {
      final scans = await storageService.loadScans();
      final scan = scans.where((s) => s.id == scanId).firstOrNull;
      if (scan != null) {
        scan.geminiPrescanStatus = 'error';
        scan.geminiPrescanError = 'Stopped by user';
        scan.geminiPrescanProgress = null;
        await storageService.updateScan(scan);
      }
    }
  }

  static Future<bool> stopAndWaitMinuteFinder(String scanId, String reason, [int timeoutMs = 10000]) async {
    if (!isMinuteFinderRunning(scanId)) return true;
    _runningControllers[scanId] = false;
    final start = DateTime.now().millisecondsSinceEpoch;
    while (isMinuteFinderRunning(scanId)) {
      if (DateTime.now().millisecondsSinceEpoch - start > timeoutMs) {
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  static Future<void> _runAsync({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    required String mode,
  }) async {
    final scans0 = await storageService.loadScans();
    final scan0 = scans0.where((s) => s.id == scanId).firstOrNull;
    if (scan0 == null || scan0.shortDuration == null || scan0.movieDuration == null) {
      throw Exception('Scan/media state missing');
    }

    final shortDuration = scan0.shortDuration!;
    final movieDuration = scan0.movieDuration!;
    final trimStart = scan0.movieTrimStart ?? 0.0;
    final trimEnd = scan0.movieTrimEnd ?? movieDuration;

    if (shortDuration > MINUTE_FINDER_MAX_SHORT_SEC) {
      throw Exception('Short video 3 minute se lamba hai (${_fmtDur(shortDuration)}) — Gemini Minute Finder sirf ≤3 min short par chalta hai.');
    }

    final mediaDir = MediaService.scanMediaDir(scanId);
    final shortFile = await MediaService.ensureLocalMedia(scanId, 'short');
    final movieFile = await MediaService.ensureLocalMedia(scanId, 'movie');

    if (shortFile == null || movieFile == null || !File(shortFile).existsSync() || !File(movieFile).existsSync()) {
      throw Exception('Short/movie file server par nahi mili — dobara upload karke retry karo.');
    }

    // Step 1: Movie upload copy
    final copyPath = p.join(mediaDir, 'prescan-movie.mp4');
    final targetCopyFile = File(copyPath);
    await targetCopyFile.parent.create(recursive: true);

    scan0.geminiPrescanStatus = 'preparing';
    scan0.geminiPrescanProgress = 'Preparing movie copy...';
    await storageService.updateScan(scan0);

    // Reuse or create movie copy
    final reused = await MediaService.findAndReusePrescanMovie(
      storageService: storageService,
      targetId: scanId,
      movieName: scan0.movieName ?? '',
      movieSize: scan0.movieSize ?? 0,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );

    double copyDuration = trimEnd - trimStart;
    if (reused != null && targetCopyFile.existsSync()) {
      copyDuration = (reused['durationSec'] as num).toDouble();
      scan0.geminiPrescanMovieDuration = copyDuration;
      scan0.geminiPrescanMovieSizeBytes = reused['sizeBytes'] as int;
      scan0.geminiPrescanMovieReencoded = reused['reencoded'] as bool;
      await storageService.updateScan(scan0);
    } else {
      final info = await ffmpegService.preparePrescanMovieCopy(
        sourceFile: movieFile,
        destFile: copyPath,
        movieDuration: movieDuration,
        trimStart: trimStart,
        trimEnd: trimEnd,
        onProgress: (pct, note) async {
          final cur = (await storageService.loadScans()).where((x) => x.id == scanId).firstOrNull;
          if (cur != null) {
            cur.geminiPrescanProgress = 'Movie copy: $note $pct%';
            await storageService.updateScan(cur);
          }
        },
      );
      copyDuration = info['durationSec'] as double;
      scan0.geminiPrescanMovieDuration = copyDuration;
      scan0.geminiPrescanMovieSizeBytes = info['sizeBytes'] as int;
      scan0.geminiPrescanMovieReencoded = info['reencoded'] as bool;
      await storageService.updateScan(scan0);
    }

    if (_runningControllers[scanId] == false) return;

    // Build 20-min windows
    final windows = <GeminiPrescanWindow>[];
    int wIdx = 0;
    for (double t = 0.0; t < copyDuration - 0.5; t += MINUTE_FINDER_WINDOW_SEC) {
      windows.add(GeminiPrescanWindow(
        index: wIdx++,
        startOffset: t,
        endOffset: min(t + MINUTE_FINDER_WINDOW_SEC, copyDuration),
        status: 'pending',
      ));
    }
    scan0.geminiPrescanWindows = windows;
    await storageService.updateScan(scan0);

    // Step 2: Upload short and movie copy to Gemini Files API
    scan0.geminiPrescanStatus = 'uploading';
    scan0.geminiPrescanProgress = 'Uploading to Gemini...';
    await storageService.updateScan(scan0);

    final uploads = <PrescanUpload>[];
    for (int kIdx = 0; kIdx < min(apiKeys.length, 3); kIdx++) {
      final key = apiKeys[kIdx];
      final keyId = hashApiKey(key);
      try {
        final shortUp = await geminiService.uploadVideo(apiKey: key, filePath: shortFile);
        final movieUp = await geminiService.uploadVideo(apiKey: key, filePath: copyPath);
        uploads.add(PrescanUpload(
          keyId: keyId,
          shortUri: shortUp['uri'] ?? '',
          shortName: shortUp['name'] ?? '',
          movieUri: movieUp['uri'] ?? '',
          movieName: movieUp['name'] ?? '',
          uploadedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } catch (_) {}
    }

    if (uploads.isEmpty) {
      throw Exception('Kisi bhi API key par upload nahi hua (short + movie copy) — key/quota check karke Retry karo.');
    }

    scan0.prescanUploads = uploads;
    scan0.geminiPrescanStatus = 'scanning';
    scan0.geminiPrescanProgress = 'Scanning windows (0/${windows.length})';
    await storageService.updateScan(scan0);

    // Step 3: Scan windows across lanes
    final coordinator = GlobalGeminiCoordinator.instance;
    final modelPool = ['gemini-3.6-flash', 'gemini-3.7-flash', 'gemini-3.8-flash'];
    int completedCount = 0;

    for (final w in windows) {
      if (_runningControllers[scanId] == false) return;
      w.status = 'running';
      await storageService.updateScan(scan0);

      // Build candidate lanes across all uploaded keys
      final candidateLanes = <CandidateLane>[];
      for (int i = 0; i < uploads.length; i++) {
        final up = uploads[i];
        final rawKey = apiKeys.firstWhere((k) => hashApiKey(k) == up.keyId, orElse: () => apiKeys[0]);
        for (final m in modelPool) {
          candidateLanes.add(CandidateLane(apiKey: rawKey, keyIdx: i + 1, modelId: m));
        }
      }

      final laneAcquired = await coordinator.acquireFirstAvailableLane(
        scanId: scanId,
        scanTitle: scan0.shortName ?? scanId,
        candidates: candidateLanes,
        operation: 'Minute Finder Window #${w.index}',
        videoSeconds: w.endOffset - w.startOffset,
        isStopping: () => _runningControllers[scanId] == false,
      );

      final CandidateLane selected = laneAcquired['selected'] as CandidateLane;
      final Function releaseLane = laneAcquired['release'] as Function;
      final activeUpload = uploads.firstWhere((u) => u.keyId == hashApiKey(selected.apiKey));

      try {
        final prompt = buildMinuteFinderPrompt(w.startOffset, w.endOffset);
        final resp = await geminiService.generateContent(
          apiKey: selected.apiKey,
          model: selected.modelId,
          parts: [
            {'fileData': {'fileUri': activeUpload.shortUri, 'mimeType': 'video/mp4'}, 'videoMetadata': {'fps': MINUTE_FINDER_SHORT_FPS}},
            {'fileData': {'fileUri': activeUpload.movieUri, 'mimeType': 'video/mp4'}, 'videoMetadata': {'startOffset': '${w.startOffset.toInt()}s', 'endOffset': '${w.endOffset.toInt()}s'}},
            {'text': prompt},
          ],
        );

        final rawText = resp['text'] ?? '';
        final parsed = parseMinuteFinderOutput(rawText, w.startOffset, w.endOffset, true);
        w.status = 'done';
        w.raw = rawText;
        w.matches = parsed.matchMinutes.length;
        w.minutes = (parsed.matchMinutes + parsed.possibleMinutes).toSet().toList()..sort();
        w.error = null;
      } catch (err) {
        w.status = 'failed';
        w.error = err.toString();
        coordinator.reportRateLimit(selected.apiKey, selected.modelId);
      } finally {
        releaseLane();
      }

      completedCount++;
      scan0.geminiPrescanProgress = 'Scanning windows ($completedCount/${windows.length})';
      await storageService.updateScan(scan0);
    }

    if (_runningControllers[scanId] == false) return;

    // Step 4: Build suggestions and apply
    final suggestions = _buildSuggestions(scan0, trimStart, trimEnd, shortDuration);
    scan0.minuteSuggestions = suggestions;

    if (suggestions.isEmpty) {
      throw Exception('Gemini Minute Finder ko koi match nahi mila — manual Full scan use karo.');
    }

    final approved = suggestions.map((s) => s.minute).toList();
    final applied = applyApprovedMinutes(scan0, approved, suggestions);
    if (!applied.ok) throw Exception(applied.error);

    scan0.geminiPrescanStatus = 'starting_scan';
    scan0.geminiPrescanProgress = 'Minutes found: ${approved.map((m) => m + 1).join(', ')} — ready';
    await storageService.updateScan(scan0);
  }

  static List<MinuteSuggestion> _buildSuggestions(Scan scan, double trimStart, double trimEnd, double shortDuration) {
    final byMinute = <int, MinuteSuggestion>{};
    final minMinute = (trimStart / 60.0).floor();
    final maxMinute = (max(trimStart, trimEnd - 0.001) / 60.0).floor();
    final fullShort = ShortWindow(start: 0.0, end: shortDuration);

    for (final w in scan.geminiPrescanWindows) {
      if (w.status != 'done' || w.raw == null || w.raw!.isEmpty) continue;
      final parsed = parseMinuteFinderOutput(w.raw!, w.startOffset, w.endOffset, true);

      for (final h in parsed.hits) {
        final a = ((trimStart + h.fileStart) / 60.0).floor() - 1;
        final b = ((trimStart + h.fileEnd - 0.001) / 60.0).floor() + 1;
        final sw = (h.shortStart != null && h.shortEnd != null)
            ? ShortWindow(start: h.shortStart!, end: h.shortEnd!)
            : fullShort;

        for (int m = a; m <= b; m++) {
          if (m < minMinute || m > maxMinute) continue;
          var sug = byMinute[m];
          if (sug == null) {
            sug = MinuteSuggestion(minute: m, sceneCount: 0, confidences: [], shortWindows: []);
            byMinute[m] = sug;
          }
          sug.sceneCount += 1;
          sug.confidences.add(h.kind);
          if (!sug.shortWindows.any((x) => (x.start - sw.start).abs() < 0.01 && (x.end - sw.end).abs() < 0.01)) {
            sug.shortWindows.add(sw);
          }
        }
      }

      for (final m in w.minutes ?? <int>[]) {
        if (m >= minMinute && m <= maxMinute && !byMinute.containsKey(m)) {
          byMinute[m] = MinuteSuggestion(minute: m, sceneCount: 1, confidences: ['possible'], shortWindows: [fullShort]);
        }
      }
    }

    final res = byMinute.values.toList();
    res.sort((a, b) => a.minute - b.minute);
    return res;
  }
}
