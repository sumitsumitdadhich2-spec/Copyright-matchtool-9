import 'dart:io';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';
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
        // Parse time progression if available
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
}
