import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;
import '../models/chunk.dart';
import '../utils/candidate_pick.dart';
import '../utils/batch_verifier_prompt.dart';

/// 1:1 Port of lib/batch-minute-stitcher.ts
/// Handles segment planning and FFmpeg stitching for 24 FPS verification.

class BatchVerifyPart {
  final int index;
  final String? matchId;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final double duration;
  final double localStart;
  final double localEnd;
  final String? candidateId;
  final String? groupId;
  final bool userPick;
  final String? batchVerified;
  final double confidence;

  BatchVerifyPart({
    required this.index,
    this.matchId,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.duration,
    required this.localStart,
    required this.localEnd,
    this.candidateId,
    this.groupId,
    this.userPick = false,
    this.batchVerified,
    this.confidence = 0.8,
  });

  BatchVerifyPartSpec toSpec() {
    return BatchVerifyPartSpec(
      index: index,
      localStart: localStart,
      localEnd: localEnd,
      shortStart: shortStart,
      shortEnd: shortEnd,
      movieStart: movieStart,
      movieEnd: movieEnd,
      chunkIndex: chunkIndex,
      duration: duration,
    );
  }
}

class StitchedMinuteResult {
  final int minuteIndex;
  final List<BatchVerifyPart> parts;
  final String shortStitchedPath;
  final String movieStitchedPath;
  final double totalDuration;

  StitchedMinuteResult({
    required this.minuteIndex,
    required this.parts,
    required this.shortStitchedPath,
    required this.movieStitchedPath,
    required this.totalDuration,
  });
}

class CandidateScore {
  final dynamic candidate; // ChunkMatch or CandidateEntry
  final String? matchId;
  final String? candidateId;
  final String? groupId;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final double score;
  final bool userPick;
  final String? batchVerified;
  final double confidence;

  CandidateScore({
    required this.candidate,
    this.matchId,
    this.candidateId,
    this.groupId,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.score,
    required this.userPick,
    this.batchVerified,
    required this.confidence,
  });
}

class BatchMinuteStitcher {
  /// Plans the non-overlapping verification segments for each 1-minute window
  static List<List<BatchVerifyPart>> planMinuteSegments({
    required List<ChunkMatch> matches,
    required List<CandidateGroup> candidateGroups,
    required double shortDuration,
    double movieTrimStart = 0.0,
    double? movieTrimEnd,
    double? movieDuration,
  }) {
    final minuteCount = (shortDuration / 60.0).ceil().clamp(1, 9999);
    final results = <List<BatchVerifyPart>>[];

    for (int minuteIdx = 0; minuteIdx < minuteCount; minuteIdx++) {
      final minStart = minuteIdx * 60.0;
      final minEnd = ((minuteIdx + 1) * 60.0).clamp(0.0, shortDuration);

      final candidateScores = <CandidateScore>[];

      // 1. Collect from candidateGroups
      for (final group in candidateGroups) {
        if (group.shortStart >= minEnd || group.shortEnd <= minStart) continue;

        for (final c in group.candidates) {
          final isUserPick = group.userPickId == c.id || c.userPick == true;
          final isConfirmed = c.batchVerified == 'confirmed' || c.verified;
          final isRejected = c.batchVerified == 'rejected';

          double score = 0.0;
          if (isUserPick) score += 10000.0;
          if (isConfirmed) score += 1000.0;
          if (isRejected) score -= 500.0;
          score += (c.shortEnd - c.shortStart).clamp(0.0, 60.0) * 10.0;
          score += (c.confidence ?? 0.8) * 10.0;

          candidateScores.add(CandidateScore(
            candidate: c,
            candidateId: c.id,
            groupId: group.id,
            shortStart: c.shortStart.clamp(minStart, minEnd),
            shortEnd: c.shortEnd.clamp(minStart, minEnd),
            movieStart: c.movieStart,
            movieEnd: c.movieEnd,
            chunkIndex: c.chunkIndex,
            score: score,
            userPick: isUserPick,
            batchVerified: c.batchVerified,
            confidence: c.confidence ?? 0.8,
          ));
        }
      }

      // 2. Collect from matches (if not already in groups)
      for (final m in matches) {
        if (m.shortStart >= minEnd || m.shortEnd <= minStart) continue;
        final alreadyAdded = candidateScores.any((cs) =>
            sameShortSegment(cs.shortStart, cs.shortEnd, m.shortStart, m.shortEnd));

        if (!alreadyAdded) {
          final isUserPick = m.userPick == true;
          final isConfirmed = m.batchVerified == 'confirmed' || m.verified;
          final isRejected = m.batchVerified == 'rejected';

          double score = 0.0;
          if (isUserPick) score += 10000.0;
          if (isConfirmed) score += 1000.0;
          if (isRejected) score -= 500.0;
          score += (m.shortEnd - m.shortStart).clamp(0.0, 60.0) * 10.0;
          score += (m.confidence) * 10.0;

          candidateScores.add(CandidateScore(
            candidate: m,
            matchId: m.id,
            shortStart: m.shortStart.clamp(minStart, minEnd),
            shortEnd: m.shortEnd.clamp(minStart, minEnd),
            movieStart: m.movieStart,
            movieEnd: m.movieEnd,
            chunkIndex: m.chunkIndex,
            score: score,
            userPick: isUserPick,
            batchVerified: m.batchVerified,
            confidence: m.confidence,
          ));
        }
      }

      // 3. Sort candidates by score descending
      candidateScores.sort((a, b) => b.score.compareTo(a.score));

      // 4. Greedy pick non-overlapping candidates
      final picked = <CandidateScore>[];
      for (final cs in candidateScores) {
        final dur = cs.shortEnd - cs.shortStart;
        if (dur < 0.2) continue; // Skip sub-frame rounding debris

        final overlaps = picked.any((p) {
          final oStart = p.shortStart > cs.shortStart ? p.shortStart : cs.shortStart;
          final oEnd = p.shortEnd < cs.shortEnd ? p.shortEnd : cs.shortEnd;
          return (oEnd - oStart) > 0.15;
        });

        if (!overlaps) {
          picked.add(cs);
        }
      }

      // 5. Sort chronologically
      picked.sort((a, b) => a.shortStart.compareTo(b.shortStart));

      // 6. Build final BatchVerifyPart list with local timeline
      final minuteParts = <BatchVerifyPart>[];
      double currentLocalClock = 0.0;

      for (int i = 0; i < picked.length; i++) {
        final p = picked[i];
        final dur = (p.shortEnd - p.shortStart).clamp(0.1, 60.0);
        final localStart = currentLocalClock;
        final localEnd = localStart + dur;
        currentLocalClock += dur;

        minuteParts.add(BatchVerifyPart(
          index: i + 1,
          matchId: p.matchId,
          candidateId: p.candidateId,
          groupId: p.groupId,
          shortStart: p.shortStart,
          shortEnd: p.shortEnd,
          movieStart: p.movieStart,
          movieEnd: p.movieEnd,
          chunkIndex: p.chunkIndex,
          duration: dur,
          localStart: localStart,
          localEnd: localEnd,
          userPick: p.userPick,
          batchVerified: p.batchVerified,
          confidence: p.confidence,
        ));
      }

      results.add(minuteParts);
    }

    return results;
  }

  /// Stitches paired 24fps CFR verification videos (Short and Movie) for a minute
  static Future<StitchedMinuteResult?> stitchMinuteVerificationClips({
    required String shortPath,
    required String moviePath,
    required List<BatchVerifyPart> parts,
    required String outputDir,
    required int minuteIndex,
    Function(int percent)? onProgress,
  }) async {
    if (parts.isEmpty) return null;

    final dir = Directory(outputDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final outShort = p.join(outputDir, 'batch_short_min_${minuteIndex.toString().padLeft(3, '0')}.mp4');
    final outMovie = p.join(outputDir, 'batch_movie_min_${minuteIndex.toString().padLeft(3, '0')}.mp4');

    // Remove existing
    for (final path in [outShort, outMovie]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }

    final totalDur = parts.fold<double>(0.0, (sum, p) => sum + p.duration);

    // Build filter_complex for Short video
    final shortFilters = <String>[];
    final shortInputs = <String>[];
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      shortInputs.addAll([
        '-ss', part.shortStart.toStringAsFixed(3),
        '-t', part.duration.toStringAsFixed(3),
        '-i', '"$shortPath"',
      ]);
      shortFilters.add('[$i:v]scale=640:-2,fps=24,setsar=1[v$i];[$i:a]aresample=48000:async=1,aformat=channel_layouts=mono[a$i]');
    }

    final concatShortV = List.generate(parts.length, (i) => '[v$i]').join('');
    final concatShortA = List.generate(parts.length, (i) => '[a$i]').join('');
    final shortComplex = '${shortFilters.join(';')};${concatShortV}concat=n=${parts.length}:v=1:a=0[outv];${concatShortA}concat=n=${parts.length}:v=0:a=1[outa]';

    final shortCmd = '''
      -y
      ${shortInputs.join(' ')}
      -filter_complex "$shortComplex"
      -map "[outv]" -map "[outa]"
      -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -fps_mode cfr
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -movflags +faststart
      "$outShort"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final shortSession = await FFmpegKit.execute(shortCmd);
    if (!ReturnCode.isSuccess(await shortSession.getReturnCode())) {
      final logs = await shortSession.getLogsAsString();
      throw Exception('Failed to stitch Short verification clip: $logs');
    }

    // Build filter_complex for Movie video
    final movieFilters = <String>[];
    final movieInputs = <String>[];
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      movieInputs.addAll([
        '-ss', part.movieStart.toStringAsFixed(3),
        '-t', part.duration.toStringAsFixed(3),
        '-i', '"$moviePath"',
      ]);
      movieFilters.add('[$i:v]scale=640:-2,fps=24,setsar=1[v$i];[$i:a]aresample=48000:async=1,aformat=channel_layouts=mono[a$i]');
    }

    final concatMovieV = List.generate(parts.length, (i) => '[v$i]').join('');
    final concatMovieA = List.generate(parts.length, (i) => '[a$i]').join('');
    final movieComplex = '${movieFilters.join(';')};${concatMovieV}concat=n=${parts.length}:v=1:a=0[outv];${concatMovieA}concat=n=${parts.length}:v=0:a=1[outa]';

    final movieCmd = '''
      -y
      ${movieInputs.join(' ')}
      -filter_complex "$movieComplex"
      -map "[outv]" -map "[outa]"
      -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p -fps_mode cfr
      -c:a aac -b:a 64k -ac 1 -ar 48000
      -movflags +faststart
      "$outMovie"
    '''.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final movieSession = await FFmpegKit.execute(movieCmd);
    if (!ReturnCode.isSuccess(await movieSession.getReturnCode())) {
      final logs = await movieSession.getLogsAsString();
      throw Exception('Failed to stitch Movie verification clip: $logs');
    }

    return StitchedMinuteResult(
      minuteIndex: minuteIndex,
      parts: parts,
      shortStitchedPath: outShort,
      movieStitchedPath: outMovie,
      totalDuration: totalDur,
    );
  }
}
