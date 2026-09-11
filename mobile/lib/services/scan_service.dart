import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import 'ffmpeg_service.dart';
import 'gemini_service.dart';
import 'storage_service.dart';

class ScanService extends ChangeNotifier {
  final FFmpegService _ffmpeg = FFmpegService();
  final GeminiService _gemini = GeminiService();
  StorageService? _storage;

  Scan? _currentScan;
  bool _isScanning = false;
  bool _shouldStop = false;

  Scan? get currentScan => _currentScan;
  bool get isScanning => _isScanning;
  FFmpegService get ffmpeg => _ffmpeg;
  GeminiService get gemini => _gemini;

  Future<void> init(StorageService storage) async {
    _storage = storage;
    await _ffmpeg.init();
  }

  void configureGemini(String apiKey, {String? model}) {
    _gemini.configure(apiKey, modelName: model);
  }

  void selectScan(Scan scan) {
    _currentScan = scan;
    notifyListeners();
  }

  /// Create a new Scan instance from selected video paths
  Future<Scan> createScan({
    required String shortPath,
    required String moviePath,
    String? selectedModel,
  }) async {
    final id = const Uuid().v4();

    // Probe media durations with local FFmpeg
    double shortDuration = 0;
    double movieDuration = 0;
    int shortSize = 0;
    int movieSize = 0;

    try {
      shortDuration = await _ffmpeg.probeDuration(shortPath);
      shortSize = await File(shortPath).length();
    } catch (e) {
      debugPrint('[ScanService] Error probing short video: $e');
    }

    try {
      movieDuration = await _ffmpeg.probeDuration(moviePath);
      movieSize = await File(moviePath).length();
    } catch (e) {
      debugPrint('[ScanService] Error probing movie video: $e');
    }

    final scan = Scan(
      id: id,
      createdAt: DateTime.now(),
      status: ScanStatus.ready,
      shortPath: shortPath,
      moviePath: moviePath,
      shortName: p.basename(shortPath),
      movieName: p.basename(moviePath),
      shortSize: shortSize,
      movieSize: movieSize,
      shortDuration: shortDuration > 0 ? shortDuration : null,
      movieDuration: movieDuration > 0 ? movieDuration : null,
      selectedModel: selectedModel,
    );

    _currentScan = scan;
    if (_storage != null) {
      await _storage!.saveScan(scan);
    }
    notifyListeners();
    return scan;
  }

  /// Start or resume scanning the current scan
  Future<void> startScan({bool autoVerify = false}) async {
    if (_currentScan == null || !_gemini.isConfigured || _isScanning) return;

    _isScanning = true;
    _shouldStop = false;
    _currentScan!.error = null;
    _currentScan!.startedAt ??= DateTime.now();

    try {
      final workDir = _storage != null
          ? await _storage!.getScanDir(_currentScan!.id)
          : Directory.systemTemp.path;
      final chunksDir = p.join(workDir, 'chunks');

      // Step 1: Chunk the movie if not already chunked
      if (_currentScan!.chunkCount == 0 || _currentScan!.chunks.isEmpty) {
        _currentScan!.status = ScanStatus.chunking;
        _currentScan!.chunkingProgress = 0;
        notifyListeners();

        final movieDuration = _currentScan!.movieDuration ??
            await _ffmpeg.probeDuration(_currentScan!.moviePath!);

        final chunkCount = await _ffmpeg.chunkMovie(
          moviePath: _currentScan!.moviePath!,
          outputDir: chunksDir,
          duration: movieDuration,
          onProgress: (pct) {
            _currentScan!.chunkingProgress = pct.toDouble();
            notifyListeners();
          },
        );

        if (_shouldStop) {
          _currentScan!.status = ScanStatus.stopped;
          notifyListeners();
          return;
        }

        _currentScan!.chunkCount = chunkCount;
        _currentScan!.chunks = List.generate(
          chunkCount,
          (i) => ChunkState(index: i),
        );
        _currentScan!.chunkingProgress = 100;
        if (_storage != null) await _storage!.saveScan(_currentScan!);
      }

      // Step 2: Scan chunks sequentially
      _currentScan!.status = ScanStatus.scanning;
      notifyListeners();

      for (int i = 0; i < _currentScan!.chunks.length; i++) {
        if (_shouldStop) break;

        final chunk = _currentScan!.chunks[i];
        // Skip already completed chunks
        if (chunk.status == ChunkStatus.match || chunk.status == ChunkStatus.noMatch) {
          continue;
        }

        chunk.status = ChunkStatus.scanning;
        chunk.attempts++;
        notifyListeners();

        final chunkFile = _ffmpeg.chunkPath(chunksDir, i);
        final chunkOffsetSec = i * 60.0;

        try {
          final result = await _gemini.mapChunk(
            shortVideoPath: _currentScan!.shortPath!,
            chunkPath: chunkFile,
            chunkIndex: i,
            chunkOffsetSeconds: chunkOffsetSec,
          );

          chunk.rawOutput = result.rawText;

          if (result.matches.isNotEmpty) {
            chunk.status = ChunkStatus.match;
            chunk.matches = result.matches;

            for (final match in result.matches) {
              // Add to global match list if not duplicate
              final exists = _currentScan!.matches.any((m) =>
                  m.chunkIndex == match.chunkIndex &&
                  (m.shortStart - match.shortStart).abs() < 0.1 &&
                  (m.movieStart - match.movieStart).abs() < 0.1);
              if (!exists) {
                _currentScan!.matches.add(match);
              }
            }
          } else {
            chunk.status = ChunkStatus.noMatch;
          }
        } catch (e) {
          chunk.status = ChunkStatus.failed;
          chunk.error = e.toString();
          debugPrint('[ScanService] Chunk $i failed: $e');
        }

        if (_storage != null) {
          await _storage!.saveScan(_currentScan!);
        }
        notifyListeners();

        // Brief delay between API calls to honor rate pacing
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (_shouldStop) {
        _currentScan!.status = ScanStatus.stopped;
      } else {
        _currentScan!.status = ScanStatus.done;
        _currentScan!.finishedAt = DateTime.now();
      }

      if (_storage != null) {
        await _storage!.saveScan(_currentScan!);
      }
    } catch (e) {
      _currentScan!.status = ScanStatus.error;
      _currentScan!.error = e.toString();
      debugPrint('[ScanService] Scan failed with fatal error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop ongoing scan
  void stopScan() {
    _shouldStop = true;
    _ffmpeg.cancelCurrentOperation();
    if (_currentScan != null) {
      _currentScan!.status = ScanStatus.stopped;
      if (_storage != null) _storage!.saveScan(_currentScan!);
      notifyListeners();
    }
  }

  /// Retry an individual chunk
  Future<void> retryChunk(int chunkIndex) async {
    if (_currentScan == null || !_gemini.isConfigured || _isScanning) return;
    if (chunkIndex < 0 || chunkIndex >= _currentScan!.chunks.length) return;

    final chunk = _currentScan!.chunks[chunkIndex];
    chunk.status = ChunkStatus.scanning;
    chunk.attempts++;
    chunk.error = null;
    notifyListeners();

    try {
      final workDir = _storage != null
          ? await _storage!.getScanDir(_currentScan!.id)
          : Directory.systemTemp.path;
      final chunksDir = p.join(workDir, 'chunks');
      final chunkFile = _ffmpeg.chunkPath(chunksDir, chunkIndex);
      final chunkOffsetSec = chunkIndex * 60.0;

      final result = await _gemini.mapChunk(
        shortVideoPath: _currentScan!.shortPath!,
        chunkPath: chunkFile,
        chunkIndex: chunkIndex,
        chunkOffsetSeconds: chunkOffsetSec,
      );

      chunk.rawOutput = result.rawText;
      if (result.matches.isNotEmpty) {
        chunk.status = ChunkStatus.match;
        chunk.matches = result.matches;
        // Remove old matches for this chunk
        _currentScan!.matches.removeWhere((m) => m.chunkIndex == chunkIndex);
        _currentScan!.matches.addAll(result.matches);
      } else {
        chunk.status = ChunkStatus.noMatch;
        _currentScan!.matches.removeWhere((m) => m.chunkIndex == chunkIndex);
      }
    } catch (e) {
      chunk.status = ChunkStatus.failed;
      chunk.error = e.toString();
    }

    if (_storage != null) {
      await _storage!.saveScan(_currentScan!);
    }
    notifyListeners();
  }

  /// Verify a candidate match by extracting micro-clips and running VERIFY_PROMPT
  Future<bool> verifyMatch(ChunkMatch match) async {
    if (_currentScan == null || !_gemini.isConfigured) return false;

    try {
      final workDir = _storage != null
          ? await _storage!.getScanDir(_currentScan!.id)
          : Directory.systemTemp.path;
      final verifyDir = Directory(p.join(workDir, 'verify'));
      if (!await verifyDir.exists()) await verifyDir.create(recursive: true);

      final shortClip = p.join(verifyDir.path, 'verify_short_${match.chunkIndex}_${match.shortStart.toInt()}.mp4');
      final movieClip = p.join(verifyDir.path, 'verify_movie_${match.chunkIndex}_${match.movieStart.toInt()}.mp4');

      // Extract short clip with 0.5s padding
      final sStart = (match.shortStart - 0.25).clamp(0.0, 36000.0);
      final sEnd = match.shortEnd + 0.25;
      await _ffmpeg.extractClip(
        sourcePath: _currentScan!.shortPath!,
        start: sStart,
        end: sEnd,
        outputPath: shortClip,
      );

      // Extract movie candidate clip
      final mStart = (match.movieStart - 0.25).clamp(0.0, 36000.0);
      final mEnd = match.movieEnd + 0.25;
      await _ffmpeg.extractClip(
        sourcePath: _currentScan!.moviePath!,
        start: mStart,
        end: mEnd,
        outputPath: movieClip,
      );

      final verifyRes = await _gemini.verifyCandidate(
        shortClipPath: shortClip,
        movieClipPath: movieClip,
      );

      match.verified = verifyRes.same;
      match.reason = verifyRes.reason;

      if (_storage != null) {
        await _storage!.saveScan(_currentScan!);
      }
      notifyListeners();
      return verifyRes.same;
    } catch (e) {
      debugPrint('[ScanService] Error verifying match: $e');
      return false;
    }
  }
}
