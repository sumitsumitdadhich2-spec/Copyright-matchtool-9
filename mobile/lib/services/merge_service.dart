import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

/// 1:1 Port of lib/merge.ts
/// Video stream probe, geometry normalization, and precise dual-video merging.

class StreamInfo {
  final VideoStreamInfo? video;
  final AudioStreamInfo? audio;

  StreamInfo({this.video, this.audio});
}

class VideoStreamInfo {
  final String codec;
  final int width;
  final int height;
  final String pixFmt;
  final double? fps;

  VideoStreamInfo({
    required this.codec,
    required this.width,
    required this.height,
    required this.pixFmt,
    this.fps,
  });
}

class AudioStreamInfo {
  final String codec;
  final int sampleRate;
  final int channels;

  AudioStreamInfo({
    required this.codec,
    required this.sampleRate,
    required this.channels,
  });
}

class MergeTarget {
  final int width;
  final int height;
  final int fps;
  final StreamInfo short;
  final StreamInfo movie;
  final String summary;

  MergeTarget({
    required this.width,
    required this.height,
    required this.fps,
    required this.short,
    required this.movie,
    required this.summary,
  });
}

class MergeService {
  static String mergedFilePath(String mediaDir) {
    return p.join(mediaDir, 'merged.mp4');
  }

  static int _even(int n) => n % 2 == 0 ? n : n + 1;

  static String _describe(VideoStreamInfo? v) {
    if (v == null) return 'no video';
    final fpsStr = v.fps != null ? ' @ ${v.fps!.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}fps' : '';
    return '${v.width}x${v.height}$fpsStr ${v.codec}';
  }

  /// Probe first video + audio stream of a file
  static Future<StreamInfo> probeStreamInfo(String file) async {
    VideoStreamInfo? videoInfo;
    AudioStreamInfo? audioInfo;

    try {
      final session = await FFprobeKit.execute('-v error -select_streams v:0 -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate -of csv=p=0 "$file"');
      final out = await session.getOutput();
      if (out != null && out.trim().isNotEmpty) {
        final parts = out.trim().split(',');
        if (parts.length >= 4) {
          final codec = parts[0];
          final w = int.tryParse(parts[1]) ?? 0;
          final h = int.tryParse(parts[2]) ?? 0;
          final pixFmt = parts[3];
          double? fps;
          if (parts.length >= 5) {
            final rateParts = parts[4].split('/');
            if (rateParts.length == 2) {
              final num = double.tryParse(rateParts[0]) ?? 0;
              final den = double.tryParse(rateParts[1]) ?? 1;
              if (den > 0) fps = num / den;
            } else {
              fps = double.tryParse(parts[4]);
            }
          }
          if (codec.isNotEmpty && w > 0 && h > 0) {
            videoInfo = VideoStreamInfo(codec: codec, width: w, height: h, pixFmt: pixFmt, fps: fps);
          }
        }
      }
    } catch (_) {}

    try {
      final session = await FFprobeKit.execute('-v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$file"');
      final out = await session.getOutput();
      if (out != null && out.trim().isNotEmpty) {
        final parts = out.trim().split(',');
        if (parts.length >= 3 && parts[0].isNotEmpty) {
          audioInfo = AudioStreamInfo(
            codec: parts[0],
            sampleRate: int.tryParse(parts[1]) ?? 48000,
            channels: int.tryParse(parts[2]) ?? 2,
          );
        }
      }
    } catch (_) {}

    return StreamInfo(video: videoInfo, audio: audioInfo);
  }

  /// Decide the shared output format based on movie stream specs
  static Future<MergeTarget> planMergeTarget(String shortFile, String movieFile) async {
    final short = await probeStreamInfo(shortFile);
    final movie = await probeStreamInfo(movieFile);

    if (short.video == null || movie.video == null) {
      throw Exception('Video stream read nahi ho paya (ffprobe fail) — ${short.video == null ? "short" : "movie"} file valid video hai kya?');
    }

    final fps = (movie.video!.fps ?? short.video!.fps ?? 24.0).round().clamp(1, 120);
    final width = _even(movie.video!.width);
    final height = _even(movie.video!.height);

    final same = short.video!.width == movie.video!.width &&
        short.video!.height == movie.video!.height &&
        ((short.video!.fps ?? fps.toDouble()) - fps).abs() < 0.01;

    final summary = same
        ? 'short ${_describe(short.video)} + movie ${_describe(movie.video)} — same geometry, target ${width}x$height @ ${fps}fps'
        : 'short ${_describe(short.video)} → scaled/padded to movie ${width}x$height @ ${fps}fps';

    return MergeTarget(
      width: width,
      height: height,
      fps: fps,
      short: short,
      movie: movie,
      summary: summary,
    );
  }

  /// Merges short + movie normalized to movie geometry into single output file
  static Future<Map<String, dynamic>> mergeVideos({
    required String shortFile,
    required String movieFile,
    required String outFile,
    required String scanId,
    Function(String log)? onLog,
    Function(int pct, String note)? onProgress,
    int crf = 20,
  }) async {
    final target = await planMergeTarget(shortFile, movieFile);
    onLog?.('ffmpeg: merge target — ${target.summary}');

    final outF = File(outFile);
    if (await outF.exists()) await outF.delete();
    await outF.parent.create(recursive: true);

    onProgress?.(10, 'Scaling and normalizing clips to ${target.width}x${target.height}...');

    // Complex filter normalization and concatenate
    final cmd = '''
      -y
      -i "$shortFile"
      -i "$movieFile"
      -filter_complex "[0:v]scale=${target.width}:${target.height}:force_original_aspect_ratio=decrease,pad=${target.width}:${target.height}:(ow-iw)/2:(oh-ih)/2,fps=${target.fps},setsar=1[v0];
                       [1:v]scale=${target.width}:${target.height}:force_original_aspect_ratio=decrease,pad=${target.width}:${target.height}:(ow-iw)/2:(oh-ih)/2,fps=${target.fps},setsar=1[v1];
                       [0:a]aresample=48000:async=1,aformat=channel_layouts=stereo[a0];
                       [1:a]aresample=48000:async=1,aformat=channel_layouts=stereo[a1];
                       [v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]"
      -map "[outv]" -map "[outa]"
      -c:v libx264 -preset veryfast -crf $crf -pix_fmt yuv420p
      -c:a aac -b:a 160k -ar 48000
      -movflags +faststart
      "$outFile"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(cmd);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getLogsAsString();
      throw Exception('Merge failed: $logs');
    }

    if (!await outF.exists() || (await outF.length()) == 0) {
      throw Exception('Merge output file empty/missing');
    }

    onProgress?.(100, 'Merge completed successfully');
    return {'target': target, 'outFile': outFile};
  }
}
