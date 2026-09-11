import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import '../utils/constants.dart';

class FFmpegService {
  static const int MAX_CPU_CORES = AppConstants.maxCpuCores; // CRITICAL: Never use > 5 cores
  static const int CHUNK_SECONDS = AppConstants.chunkSeconds; // 60 seconds
  static const int SCAN_FPS = AppConstants.scanFps; // 24 fps forensic precision

  int _availableCores = 2;
  FFmpegSession? _activeSession;

  int get threadCount => _availableCores;

  Future<void> init() async {
    int deviceCores = Platform.numberOfProcessors;
    // CRITICAL CPU LIMITING: Limit to MAX_CPU_CORES (5) max, prevent crash and thermal throttling on 8+ core devices
    _availableCores = deviceCores.clamp(1, MAX_CPU_CORES);
  }

  /// Probe video duration in seconds using FFmpeg
  Future<double> probeDuration(String filePath) async {
    final session = await FFmpegKit.execute('-i "$filePath" -f null -');
    final logs = await session.getLogs();

    final durationRegex = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)');
    for (final log in logs) {
      final message = log.getMessage();
      final match = durationRegex.firstMatch(message);
      if (match != null) {
        final hours = int.parse(match.group(1)!);
        final minutes = int.parse(match.group(2)!);
        final seconds = double.parse(match.group(3)!);
        return hours * 3600.0 + minutes * 60.0 + seconds;
      }
    }
    // Fallback: examine full output if regex in logs missed
    final output = await session.getOutput() ?? '';
    final outMatch = durationRegex.firstMatch(output);
    if (outMatch != null) {
      final hours = int.parse(outMatch.group(1)!);
      final minutes = int.parse(outMatch.group(2)!);
      final seconds = double.parse(outMatch.group(3)!);
      return hours * 3600.0 + minutes * 60.0 + seconds;
    }
    throw Exception('Could not determine video duration for: $filePath');
  }

  /// Chunk movie into 1-minute segments at 24fps/640px with CPU thread capping
  Future<int> chunkMovie({
    required String moviePath,
    required String outputDir,
    required double duration,
    double trimStart = 0,
    double? trimEnd,
    Function(int percent)? onProgress,
  }) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final rangeEnd = trimEnd ?? duration;
    final rangeDur = (rangeEnd - trimStart).clamp(0.1, duration);

    // Compute estimated chunks
    final expectedChunks = (rangeDur / CHUNK_SECONDS).ceil();

    final command = '''
      -y
      -ss ${trimStart.toStringAsFixed(3)}
      -i "$moviePath"
      -t ${rangeDur.toStringAsFixed(3)}
      -vf "scale=640:-2,fps=$SCAN_FPS"
      -c:v libx264 -preset veryfast -crf 28
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -threads $_availableCores
      -f segment
      -segment_time $CHUNK_SECONDS
      -reset_timestamps 1
      "$outputDir/chunk-%04d.mp4"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        _activeSession = null;
      },
      (log) {
        final timeMatch = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(log.getMessage());
        if (timeMatch != null && onProgress != null) {
          final h = int.parse(timeMatch.group(1)!);
          final m = int.parse(timeMatch.group(2)!);
          final s = double.parse(timeMatch.group(3)!);
          final current = h * 3600 + m * 60 + s;
          final pct = ((current / rangeDur) * 100).clamp(0, 100).toInt();
          onProgress(pct);
        }
      },
      null,
    );
    _activeSession = session;

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      if (ReturnCode.isCancel(returnCode)) {
        throw Exception('FFmpeg chunking was cancelled');
      }
      final logs = await session.getLogsAsString();
      throw Exception('FFmpeg chunking failed: $logs');
    }

    // Count generated chunks
    final chunkFiles = dir
        .listSync()
        .where((f) => f.path.endsWith('.mp4') && p.basename(f.path).startsWith('chunk-'))
        .toList();

    return chunkFiles.isNotEmpty ? chunkFiles.length : expectedChunks;
  }

  /// Slices short video into 1-minute segments at 24fps/640px
  Future<int> segmentShortVideo({
    required String shortPath,
    required String outputDir,
    required double duration,
    Function(int percent)? onProgress,
  }) async {
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final totalSegments = (duration / CHUNK_SECONDS).ceil().clamp(1, 9999);

    final command = '''
      -y
      -i "$shortPath"
      -vf "scale=640:-2,fps=$SCAN_FPS"
      -c:v libx264 -preset veryfast -crf 28
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -threads $_availableCores
      -f segment
      -segment_time $CHUNK_SECONDS
      -reset_timestamps 1
      "$outputDir/short_segment_%03d.mp4"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.executeAsync(
      command,
      (session) async {
        _activeSession = null;
      },
      (log) {
        final timeMatch = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(log.getMessage());
        if (timeMatch != null && onProgress != null) {
          final h = int.parse(timeMatch.group(1)!);
          final m = int.parse(timeMatch.group(2)!);
          final s = double.parse(timeMatch.group(3)!);
          final current = h * 3600 + m * 60 + s;
          final pct = ((current / duration) * 100).clamp(0, 100).toInt();
          onProgress(pct);
        }
      },
      null,
    );
    _activeSession = session;

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      if (ReturnCode.isCancel(returnCode)) {
        throw Exception('Short segmenting was cancelled');
      }
      final logs = await session.getLogsAsString();
      throw Exception('Short segmenting failed: $logs');
    }

    final segmentFiles = dir
        .listSync()
        .where((f) => f.path.endsWith('.mp4') && p.basename(f.path).startsWith('short_segment_'))
        .toList();

    return segmentFiles.isNotEmpty ? segmentFiles.length : totalSegments;
  }

  /// Extract a clip from source video for verification (short or movie window)
  Future<void> extractClip({
    required String sourcePath,
    required double start,
    required double end,
    required String outputPath,
  }) async {
    final duration = (end - start).clamp(0.1, 36000.0);

    final command = '''
      -y
      -ss ${start.toStringAsFixed(3)}
      -i "$sourcePath"
      -t ${duration.toStringAsFixed(3)}
      -vf "scale=640:-2,fps=$SCAN_FPS"
      -c:v libx264 -preset veryfast -crf 28
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -threads $_availableCores
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      throw Exception('FFmpeg clip extraction failed: $logs');
    }
  }

  /// Render Side-by-Side forensic comparison video on device
  Future<void> renderSideBySide({
    required String shortPath,
    required String moviePath,
    required double shortStart,
    required double movieStart,
    required double duration,
    required String outputPath,
    Function(int percent)? onProgress,
  }) async {
    final validDur = duration.clamp(0.5, 3600.0);

    // Stack horizontally Short (left) and Movie (right) with labels
    final command = '''
      -y
      -ss ${shortStart.toStringAsFixed(3)} -t ${validDur.toStringAsFixed(3)} -i "$shortPath"
      -ss ${movieStart.toStringAsFixed(3)} -t ${validDur.toStringAsFixed(3)} -i "$moviePath"
      -filter_complex "[0:v]scale=480:360:force_original_aspect_ratio=decrease,pad=480:360:(ow-iw)/2:(oh-ih)/2,drawtext=text='SHORT CLIP':x=10:y=10:fontsize=18:fontcolor=yellow:box=1:boxcolor=black@0.6[left];[1:v]scale=480:360:force_original_aspect_ratio=decrease,pad=480:360:(ow-iw)/2:(oh-ih)/2,drawtext=text='MOVIE MATCH':x=10:y=10:fontsize=18:fontcolor=cyan:box=1:boxcolor=black@0.6[right];[left][right]hstack=inputs=2[v]"
      -map "[v]" -map 0:a?
      -c:v libx264 -preset veryfast -crf 26
      -c:a aac -b:a 128k
      -threads $_availableCores
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.executeAsync(
      command,
      (s) async => _activeSession = null,
      (log) {
        final timeMatch = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').firstMatch(log.getMessage());
        if (timeMatch != null && onProgress != null) {
          final h = int.parse(timeMatch.group(1)!);
          final m = int.parse(timeMatch.group(2)!);
          final s = double.parse(timeMatch.group(3)!);
          final current = h * 3600 + m * 60 + s;
          final pct = ((current / validDur) * 100).clamp(0, 100).toInt();
          onProgress(pct);
        }
      },
    );
    _activeSession = session;

    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      throw Exception('Side-by-side render failed: $logs');
    }
  }

  /// Render clean cut from movie
  Future<void> renderCleanCut({
    required String moviePath,
    required double start,
    required double end,
    required String outputPath,
  }) async {
    final dur = (end - start).clamp(0.2, 36000.0);
    final command = '''
      -y
      -ss ${start.toStringAsFixed(3)}
      -i "$moviePath"
      -t ${dur.toStringAsFixed(3)}
      -c:v libx264 -preset veryfast -crf 22
      -c:a aac -b:a 128k
      -threads $_availableCores
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getLogsAsString();
      throw Exception('Clean cut render failed: $logs');
    }
  }

  /// Prepare prescan movie upload copy (stream copy if <= 2GB, 480p/24fps CRF 30 if > 2GB)
  Future<Map<String, dynamic>> preparePrescanMovieCopy({
    required String moviePath,
    required String outputPath,
    required double movieDuration,
    double trimStart = 0.0,
    double? trimEnd,
    Function(int percent, String note)? onProgress,
  }) async {
    final rangeEnd = trimEnd ?? movieDuration;
    final rangeDur = (rangeEnd - trimStart).clamp(0.1, movieDuration);
    final file = File(moviePath);
    final sourceSize = await file.length();
    const maxBytes = 1.95 * 1024 * 1024 * 1024; // 1.95 GB limit for Gemini

    final fullRange = trimStart <= 0.05 && (rangeEnd - movieDuration).abs() <= 0.05;

    // Case 1: <= 2 GB and full range -> direct reuse / copy
    if (sourceSize <= maxBytes && fullRange) {
      onProgress?.(0, 'Source <= 2 GB — direct reuse (no re-encode)');
      final outF = File(outputPath);
      if (await outF.exists()) await outF.delete();
      await outF.parent.create(recursive: true);
      await file.copy(outputPath);
      onProgress?.(100, 'Movie copy ready (direct copy)');
      return {'durationSec': movieDuration, 'sizeBytes': sourceSize, 'reencoded': false};
    }

    // Case 2: <= 2 GB and trimmed -> fast stream copy
    if (sourceSize <= maxBytes && !fullRange) {
      try {
        onProgress?.(0, 'Fast stream copy for trim (no re-encode)...');
        final outF = File(outputPath);
        if (await outF.exists()) await outF.delete();
        await outF.parent.create(recursive: true);

        final cmd = '''
          -y
          -ss ${trimStart.toStringAsFixed(3)}
          -to ${rangeEnd.toStringAsFixed(3)}
          -i "$moviePath"
          -c copy
          -avoid_negative_ts make_zero
          "$outputPath"
        '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

        final session = await FFmpegKit.execute(cmd);
        if (ReturnCode.isSuccess(await session.getReturnCode())) {
          final sz = await outF.length();
          if (sz > 0 && sz <= maxBytes) {
            onProgress?.(100, 'Movie trim copy ready (stream copy)');
            return {'durationSec': rangeDur, 'sizeBytes': sz, 'reencoded': false};
          }
        }
      } catch (_) {}
    }

    // Case 3: > 2 GB -> re-encode to 480p / 24fps / CRF 30
    onProgress?.(0, 'Movie > 2 GB: 480p re-encode for Gemini...');
    final outF = File(outputPath);
    if (await outF.exists()) await outF.delete();
    await outF.parent.create(recursive: true);

    final cmd = '''
      -y
      -ss ${trimStart.toStringAsFixed(3)}
      -t ${rangeDur.toStringAsFixed(3)}
      -i "$moviePath"
      -vf "scale='min(640,iw)':-2,fps=$SCAN_FPS"
      -c:v libx264 -preset veryfast -crf 30
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -threads $_availableCores
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(cmd);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getLogsAsString();
      throw Exception('Prescan movie copy failed: $logs');
    }

    final finalSz = await outF.length();
    onProgress?.(100, 'Movie copy ready');
    return {'durationSec': rangeDur, 'sizeBytes': finalSz, 'reencoded': true};
  }

  /// Create a sanitized, silent (-an) copy of video
  Future<void> sanitizeVideoMute({
    required String sourcePath,
    required String outputPath,
  }) async {
    final cmd = '''
      -y
      -i "$sourcePath"
      -an
      -vf "scale=640:-2,fps=$SCAN_FPS,eq=contrast=0.96:brightness=0.02"
      -c:v libx264 -preset veryfast -crf 28
      -threads $_availableCores
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(cmd);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getLogsAsString();
      throw Exception('Sanitize video mute failed: $logs');
    }
  }

  /// Fast web preview generator in background
  void triggerFastPreview(String moviePath, String outputPath) {
    Future.microtask(() async {
      try {
        final outF = File(outputPath);
        if (await outF.exists() && await outF.length() > 1000) return;
        final tempPath = '$outputPath.tmp.mp4';
        final cmd = '''
          -y
          -i "$moviePath"
          -vf "scale='min(640,iw)':-2,fps=24"
          -c:v libx264 -preset ultrafast -crf 32
          -c:a aac -b:a 64k -ac 1
          -threads $_availableCores
          -movflags +faststart
          "$tempPath"
        '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

        final session = await FFmpegKit.execute(cmd);
        if (ReturnCode.isSuccess(await session.getReturnCode())) {
          final tempF = File(tempPath);
          if (await tempF.exists()) {
            await tempF.rename(outputPath);
          }
        }
      } catch (_) {}
    });
  }

  /// Cancel any ongoing FFmpeg job
  void cancelCurrentOperation() {
    if (_activeSession != null) {
      FFmpegKit.cancel(_activeSession!.getSessionId());
      _activeSession = null;
    }
  }

  /// Helper to get formatted chunk file path
  String chunkPath(String outputDir, int index) {
    return p.join(outputDir, 'chunk-${index.toString().padLeft(4, '0')}.mp4');
  }

  /// Helper to get formatted short segment file path
  String shortSegmentPath(String outputDir, int index) {
    return p.join(outputDir, 'short_segment_${index.toString().padLeft(3, '0')}.mp4');
  }
}
