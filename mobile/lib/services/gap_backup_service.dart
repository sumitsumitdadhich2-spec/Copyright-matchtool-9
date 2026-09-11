import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import '../models/chunk.dart';
import '../models/scan.dart';
import 'gemini_service.dart';
import 'storage_service.dart';

/// 1:1 Port of lib/gap-backup.ts
/// Missing scene finder and manual gap recovery engine.

const double COVERAGE_MIN_GAP_SEC = 0.5;
const int BACKUP_GAP_SEPARATOR_SEC = 1;

class ShortRange {
  final double start;
  final double end;
  ShortRange({required this.start, required this.end});
}

class GapBackupPart {
  final int index;
  final int minuteIndex;
  final double shortStart;
  final double shortEnd;
  final double gapStart;
  final double gapEnd;
  double clipStart;
  double clipEnd;
  String result; // 'pending' | 'found' | 'unresolved' | 'accepted' | 'rejected'

  GapBackupPart({
    required this.index,
    required this.minuteIndex,
    required this.shortStart,
    required this.shortEnd,
    required this.gapStart,
    required this.gapEnd,
    this.clipStart = 0.0,
    this.clipEnd = 0.0,
    this.result = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'minuteIndex': minuteIndex,
    'shortStart': shortStart,
    'shortEnd': shortEnd,
    'gapStart': gapStart,
    'gapEnd': gapEnd,
    'clipStart': clipStart,
    'clipEnd': clipEnd,
    'result': result,
  };

  factory GapBackupPart.fromJson(Map<String, dynamic> json) => GapBackupPart(
    index: json['index'] ?? 0,
    minuteIndex: json['minuteIndex'] ?? 0,
    shortStart: (json['shortStart'] as num?)?.toDouble() ?? 0.0,
    shortEnd: (json['shortEnd'] as num?)?.toDouble() ?? 0.0,
    gapStart: (json['gapStart'] as num?)?.toDouble() ?? 0.0,
    gapEnd: (json['gapEnd'] as num?)?.toDouble() ?? 0.0,
    clipStart: (json['clipStart'] as num?)?.toDouble() ?? 0.0,
    clipEnd: (json['clipEnd'] as num?)?.toDouble() ?? 0.0,
    result: json['result'] ?? 'pending',
  );
}

class GapBackupCandidate {
  final String id;
  final int part;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final String source;
  final int chunkIndex;
  final String model;
  final double confidence;
  final String? reason;
  String review; // 'pending' | 'accepted' | 'rejected'
  final int createdAt;

  GapBackupCandidate({
    required this.id,
    required this.part,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    this.source = 'gap-backup',
    required this.chunkIndex,
    required this.model,
    this.confidence = 1.0,
    this.reason,
    this.review = 'pending',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'part': part,
    'shortStart': shortStart,
    'shortEnd': shortEnd,
    'movieStart': movieStart,
    'movieEnd': movieEnd,
    'source': source,
    'chunkIndex': chunkIndex,
    'model': model,
    'confidence': confidence,
    'reason': reason,
    'review': review,
    'createdAt': createdAt,
  };

  factory GapBackupCandidate.fromJson(Map<String, dynamic> json) => GapBackupCandidate(
    id: json['id'] ?? '',
    part: json['part'] ?? 0,
    shortStart: (json['shortStart'] as num?)?.toDouble() ?? 0.0,
    shortEnd: (json['shortEnd'] as num?)?.toDouble() ?? 0.0,
    movieStart: (json['movieStart'] as num?)?.toDouble() ?? 0.0,
    movieEnd: (json['movieEnd'] as num?)?.toDouble() ?? 0.0,
    source: json['source'] ?? 'gap-backup',
    chunkIndex: json['chunkIndex'] ?? 0,
    model: json['model'] ?? 'gemini-3.5-flash',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    reason: json['reason'],
    review: json['review'] ?? 'pending',
    createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
  );
}

class GapBackupService {
  static final Map<String, bool> _activeJobs = {};

  static bool isRunning(String scanId) => _activeJobs[scanId] == true;

  static void stop(String scanId) {
    if (_activeJobs.containsKey(scanId)) {
      _activeJobs[scanId] = false;
    }
  }

  /// Calculates uncovered ranges in the short video
  static List<ShortRange> uncovered(Scan scan) {
    final total = scan.shortDuration ?? 0.0;
    if (total <= 0) return [];

    final matches = scan.matches;
    final ranges = matches.map((m) => ShortRange(start: m.shortStart, end: m.shortEnd)).toList();
    ranges.sort((a, b) => a.start.compareTo(b.start));

    // Merge overlapping ranges
    final merged = <ShortRange>[];
    for (final r in ranges) {
      if (merged.isEmpty) {
        merged.add(r);
      } else {
        final last = merged.last;
        if (r.start <= last.end + 0.1) {
          merged[merged.length - 1] = ShortRange(
            start: last.start,
            end: r.end > last.end ? r.end : last.end,
          );
        } else {
          merged.add(r);
        }
      }
    }

    // Find gaps
    final gaps = <ShortRange>[];
    double cursor = 0.0;
    for (final m in merged) {
      if (m.start - cursor >= COVERAGE_MIN_GAP_SEC) {
        gaps.add(ShortRange(start: cursor, end: m.start));
      }
      cursor = m.end > cursor ? m.end : cursor;
    }
    if (total - cursor >= COVERAGE_MIN_GAP_SEC) {
      gaps.add(ShortRange(start: cursor, end: total));
    }

    return gaps;
  }

  /// Breaks gaps into 1-minute parts
  static List<GapBackupPart> buildParts(List<ShortRange> gaps) {
    final parts = <GapBackupPart>[];
    for (final gap in gaps) {
      double cursor = gap.start;
      while (cursor < gap.end - 0.001) {
        final minuteIndex = (cursor / 60.0).floor();
        final end = gap.end < (minuteIndex + 1) * 60.0 ? gap.end : (minuteIndex + 1) * 60.0;
        parts.add(GapBackupPart(
          index: parts.length + 1,
          minuteIndex: minuteIndex,
          shortStart: cursor,
          shortEnd: end,
          gapStart: cursor,
          gapEnd: end,
        ));
        cursor = end;
      }
    }
    return parts;
  }

  /// Builds a stitched clip of missing gap pieces with 1-second black frames between parts
  static Future<Map<String, dynamic>> buildBackupClip({
    required String shortPath,
    required List<GapBackupPart> parts,
    required String outputPath,
  }) async {
    final dir = Directory(p.dirname(outputPath));
    if (!await dir.exists()) await dir.create(recursive: true);

    final args = <String>['-y'];
    final partOffsets = <Map<String, double>>[];
    double clock = 0.0;

    for (final part in parts) {
      final s = part.shortStart.clamp(0.0, 360000.0);
      final dur = (part.shortEnd - part.shortStart).clamp(0.1, 3600.0);
      args.addAll(['-ss', s.toStringAsFixed(3), '-t', dur.toStringAsFixed(3), '-i', '"$shortPath"']);
      partOffsets.add({'clipStart': clock, 'clipEnd': clock + dur});
      clock += dur + BACKUP_GAP_SEPARATOR_SEC;
    }

    final total = (clock - BACKUP_GAP_SEPARATOR_SEC).clamp(0.1, 360000.0);

    final filterChains = <String>[];
    for (int i = 0; i < parts.length; i++) {
      final isLast = i == parts.length - 1;
      final vpad = isLast ? '' : ',tpad=stop_mode=add:stop_duration=$BACKUP_GAP_SEPARATOR_SEC:color=black';
      filterChains.add('[$i:v]scale=640:-2,fps=24,setsar=1$vpad[v$i]');
      final apad = isLast ? '' : ',apad=pad_dur=$BACKUP_GAP_SEPARATOR_SEC';
      filterChains.add('[$i:a]aresample=48000:async=1,aformat=channel_layouts=mono$apad[a$i]');
    }

    final vLabels = List.generate(parts.length, (i) => '[v$i]').join('');
    final aLabels = List.generate(parts.length, (i) => '[a$i]').join('');
    filterChains.add('${vLabels}concat=n=${parts.length}:v=1:a=0[outv];${aLabels}concat=n=${parts.length}:v=0:a=1[outa]');

    final cmd = '''
      -y
      ${args.join(' ')}
      -filter_complex "${filterChains.join(';')}"
      -map "[outv]" -map "[outa]"
      -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -fps_mode cfr
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -movflags +faststart
      "$outputPath"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final session = await FFmpegKit.execute(cmd);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      final logs = await session.getLogsAsString();
      throw Exception('Failed to build backup gap clip: $logs');
    }

    for (int i = 0; i < parts.length; i++) {
      parts[i].clipStart = partOffsets[i]['clipStart']!;
      parts[i].clipEnd = partOffsets[i]['clipEnd']!;
    }

    return {
      'durationSec': total,
      'parts': partOffsets,
    };
  }

  /// Accepts or rejects a Gemini missing-scene candidate
  static Future<bool> reviewGapCandidate({
    required Scan scan,
    required StorageService storageService,
    required String candidateId,
    required String decision, // 'accept' | 'reject'
  }) async {
    final candidate = scan.gapBackupCandidates.where((c) => c.id == candidateId).firstOrNull;
    if (candidate == null) return false;

    if (decision == 'accept') {
      // Reject all other candidates for this part
      for (final item in scan.gapBackupCandidates) {
        if (item.part == candidate.part && item.id != candidate.id && item.review == 'pending') {
          item.review = 'rejected';
        }
      }
      candidate.review = 'accepted';

      // Add to active matches
      final newMatch = ChunkMatch(
        id: candidate.id,
        chunkIndex: candidate.chunkIndex,
        shortStart: candidate.shortStart,
        shortEnd: candidate.shortEnd,
        movieStart: candidate.movieStart,
        movieEnd: candidate.movieEnd,
        confidence: candidate.confidence,
        verified: true,
        model: candidate.model,
        reason: candidate.reason,
        origin: 'gap-backup',
        userPick: true,
      );

      // Replace any existing match at this short timestamp
      scan.matches = scan.matches.where((m) => !(m.origin == 'gap-backup' && (m.shortStart - candidate.shortStart).abs() < 0.1)).toList();
      scan.matches.add(newMatch);
      scan.matches.sort((a, b) => a.shortStart.compareTo(b.shortStart));
    } else {
      candidate.review = 'rejected';
    }

    await storageService.saveScan(scan);
    return true;
  }
}
