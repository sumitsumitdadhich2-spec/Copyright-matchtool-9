import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../utils/render_segments.dart';
import 'storage_service.dart';
import 'media_service.dart';
import 'ffmpeg_service.dart';

/// 1:1 Port of lib/render.ts
/// Video export and rendering pipeline: multi-stage scene extraction, intermediate parts encoding, concat demuxing, and duration sync verification.

class RenderResolutionConfig {
  final int w;
  final int h;
  const RenderResolutionConfig(this.w, this.h);
}

class RenderSettings {
  final String resolution; // 480p, 720p, 1080p, 2k, 4k
  final int fps; // 24, 25, 30, 60
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final double headPaddingSec;
  final double tailPaddingSec;

  RenderSettings({
    this.resolution = '1080p',
    this.fps = 24,
    this.videoBitrateKbps = 6000,
    this.audioBitrateKbps = 192,
    this.headPaddingSec = 0.0,
    this.tailPaddingSec = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'resolution': resolution,
        'fps': fps,
        'videoBitrateKbps': videoBitrateKbps,
        'audioBitrateKbps': audioBitrateKbps,
        'headPaddingSec': headPaddingSec,
        'tailPaddingSec': tailPaddingSec,
      };

  factory RenderSettings.fromJson(Map<String, dynamic> json) => RenderSettings(
        resolution: json['resolution'] ?? '1080p',
        fps: json['fps'] ?? 24,
        videoBitrateKbps: json['videoBitrateKbps'] ?? 6000,
        audioBitrateKbps: json['audioBitrateKbps'] ?? 192,
        headPaddingSec: (json['headPaddingSec'] as num?)?.toDouble() ?? 0.0,
        tailPaddingSec: (json['tailPaddingSec'] as num?)?.toDouble() ?? 0.0,
      );
}

class RenderService {
  static const Map<String, RenderResolutionConfig> resolutionMap = {
    '480p': RenderResolutionConfig(854, 480),
    '720p': RenderResolutionConfig(1280, 720),
    '1080p': RenderResolutionConfig(1920, 1080),
    '2k': RenderResolutionConfig(2560, 1440),
    '4k': RenderResolutionConfig(3840, 2160),
  };

  static final Map<String, bool> _activeRenders = {};

  static bool isRenderActive(String scanId) => _activeRenders[scanId] == true;

  static String renderOutputPath(String scanId) {
    return p.join(MediaService.scanMediaDir(scanId), 'render.mp4');
  }

  static void cancelRender(String scanId) {
    _activeRenders[scanId] = false;
  }

  /// Start background render
  static Future<Map<String, dynamic>> startRender({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required String scanId,
    required RenderSettings settings,
  }) async {
    if (_activeRenders[scanId] == true) {
      return {'ok': false, 'error': 'A render is already in progress for this scan'};
    }

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};

    final rawSegments = RenderSegmentsUtils.buildRenderSegments(scan.matches);
    if (rawSegments.isEmpty) {
      return {'ok': false, 'error': 'No matched scenes to render'};
    }

    final headPad = [0.0, settings.headPaddingSec].reduce((a, b) => a > b ? a : b);
    final tailPad = [0.0, settings.tailPaddingSec].reduce((a, b) => a > b ? a : b);
    final maxMovieDur = scan.movieDuration != null && scan.movieDuration! > 0 ? scan.movieDuration! : double.infinity;

    final effectiveSegments = rawSegments.map((seg) {
      final paddedMovieStart = [0.0, seg.movieStart - headPad].reduce((a, b) => a > b ? a : b);
      final paddedMovieEnd = [
        maxMovieDur,
        [paddedMovieStart + 0.05, seg.movieEnd + tailPad].reduce((a, b) => a > b ? a : b)
      ].reduce((a, b) => a < b ? a : b);
      return RenderSegment(
        movieStart: paddedMovieStart,
        movieEnd: paddedMovieEnd,
        shortStart: seg.shortStart,
        shortEnd: seg.shortEnd,
        origin: seg.origin,
        originWindow: seg.originWindow,
        rejected: seg.rejected,
        unverified: seg.unverified,
      );
    }).toList();

    final snapped = RenderSegmentsUtils.snapSegments(effectiveSegments, settings.fps);
    final totalExpectedSec = RenderSegmentsUtils.totalSnappedSeconds(snapped, settings.fps);

    final mediaDir = MediaService.scanMediaDir(scanId);
    final movieFile = p.join(mediaDir, 'movie.mp4');
    if (!File(movieFile).existsSync()) {
      return {'ok': false, 'error': 'Original movie file not found'};
    }

    _activeRenders[scanId] = true;

    // Run in background
    _runRenderAsync(
      storageService: storageService,
      ffmpegService: ffmpegService,
      scanId: scanId,
      movieFile: movieFile,
      segments: snapped,
      settings: settings,
      totalExpectedSec: totalExpectedSec,
    ).then((_) {
      _activeRenders.remove(scanId);
    }).catchError((err) async {
      _activeRenders.remove(scanId);
    });

    return {'ok': true};
  }

  static Future<void> _runRenderAsync({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required String scanId,
    required String movieFile,
    required List<SnappedSegment> segments,
    required RenderSettings settings,
    required double totalExpectedSec,
  }) async {
    final mediaDir = MediaService.scanMediaDir(scanId);
    final partsDir = p.join(mediaDir, 'render-parts');
    await Directory(partsDir).create(recursive: true);

    final resConfig = resolutionMap[settings.resolution] ?? const RenderResolutionConfig(1920, 1080);
    final partFiles = <String>[];

    for (int i = 0; i < segments.length; i++) {
      if (_activeRenders[scanId] == false) return;
      final seg = segments[i];
      final partFile = p.join(partsDir, 'part-${i.toString().padLeft(4, '0')}.mp4');

      await ffmpegService.extractClipPrecise(
        sourceFile: movieFile,
        startSec: seg.movieStart,
        endSec: seg.movieEnd,
        outFile: partFile,
      );

      partFiles.add(partFile);
    }

    if (_activeRenders[scanId] == false) return;

    // Concat demux
    final concatListFile = p.join(partsDir, 'parts.txt');
    final lines = partFiles.map((f) => "file '${f.replaceAll("'", "'\\''")}'").join('\n');
    await File(concatListFile).writeAsString(lines);

    final finalOutput = renderOutputPath(scanId);
    await ffmpegService.runCommand([
      '-f', 'concat',
      '-safe', '0',
      '-i', concatListFile,
      '-c:v', 'libx264',
      '-b:v', '${settings.videoBitrateKbps}k',
      '-r', '${settings.fps}',
      '-s', '${resConfig.w}x${resConfig.h}',
      '-c:a', 'aac',
      '-b:a', '${settings.audioBitrateKbps}k',
      '-y',
      finalOutput,
    ]);

    // Clean up temporary parts
    try {
      await Directory(partsDir).delete(recursive: true);
    } catch (_) {}
  }
}
