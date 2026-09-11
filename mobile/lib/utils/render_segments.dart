import '../models/scan.dart';

/// 1:1 Port of lib/render-segments.ts
/// Single source of truth for both instant preview and exported scene order.

class RenderSegment {
  double movieStart;
  double movieEnd;
  double shortStart;
  double shortEnd;
  String? origin;
  int? originWindow;
  bool? rejected;
  bool? unverified;

  RenderSegment({
    required this.movieStart,
    required this.movieEnd,
    required this.shortStart,
    required this.shortEnd,
    this.origin,
    this.originWindow,
    this.rejected,
    this.unverified,
  });

  Map<String, dynamic> toJson() => {
        'movieStart': movieStart,
        'movieEnd': movieEnd,
        'shortStart': shortStart,
        'shortEnd': shortEnd,
        if (origin != null) 'origin': origin,
        if (originWindow != null) 'originWindow': originWindow,
        if (rejected != null) 'rejected': rejected,
        if (unverified != null) 'unverified': unverified,
      };
}

class SnappedSegment extends RenderSegment {
  final int frames;
  final double snapDur;

  SnappedSegment({
    required super.movieStart,
    required super.movieEnd,
    required super.shortStart,
    required super.shortEnd,
    super.origin,
    super.originWindow,
    super.rejected,
    super.unverified,
    required this.frames,
    required this.snapDur,
  });
}

class RenderSegmentsUtils {
  /// Build render segments obeying all ordering rules, verified preference, trimming, continuity merge, and deduplication
  static List<RenderSegment> buildRenderSegments(List<ScanMatch> rawMatches) {
    final matches = rawMatches.where((m) => m.movieEnd - m.movieStart > 0.05).toList();

    matches.sort((a, b) {
      if (a.shortStart != b.shortStart) return a.shortStart.compareTo(b.shortStart);
      final aPick = a.userPick == true ? 1 : 0;
      final bPick = b.userPick == true ? 1 : 0;
      if (bPick != aPick) return bPick.compareTo(aPick);

      final aVerif = (a.verified == true || a.batchVerified == 'confirmed') ? 1 : 0;
      final bVerif = (b.verified == true || b.batchVerified == 'confirmed') ? 1 : 0;
      if (bVerif != aVerif) return bVerif.compareTo(aVerif);

      final aConf = a.confidence ?? 0.0;
      final bConf = b.confidence ?? 0.0;
      if (bConf != aConf) return bConf.compareTo(aConf);

      return a.movieStart.compareTo(b.movieStart);
    });

    final segments = <RenderSegment>[];

    for (final match in matches) {
      double shortStart = match.shortStart;
      double movieStart = match.movieStart;
      final double shortEnd = match.shortEnd;
      final double movieEnd = match.movieEnd;
      final previous = segments.isNotEmpty ? segments.last : null;

      final isUnverifiedCandidate =
          match.userPick != true && match.verified != true && match.batchVerified != 'confirmed';

      // If unverified and already covered by verified/user-picked segment, skip
      if (isUnverifiedCandidate) {
        final alreadyCovered = segments.any(
          (s) =>
              s.unverified != true &&
              s.rejected != true &&
              ((s.shortStart - shortStart).abs() < 0.25 ||
                  ([0.0, [s.shortEnd, shortEnd].reduce((a, b) => a < b ? a : b) - [s.shortStart, shortStart].reduce((a, b) => a > b ? a : b)].reduce((a, b) => a > b ? a : b)) > 0.1),
        );
        if (alreadyCovered) continue;
      }

      if (previous != null) {
        final overlap = previous.shortEnd - shortStart;
        if (overlap > 0.05) {
          final prevDuration = previous.shortEnd - previous.shortStart;
          final currDuration = shortEnd - shortStart;
          final shorter = [prevDuration, currDuration].reduce((a, b) => a < b ? a : b);
          final isSameSegment = (shorter > 0 && overlap / shorter >= 0.35) ||
              overlap >= 0.35 ||
              shortEnd <= previous.shortEnd + 0.05;

          if (isSameSegment) continue;

          if (previous.unverified != true && previous.rejected != true && isUnverifiedCandidate) {
            continue;
          }

          // Partial boundary overlap
          movieStart += previous.shortEnd - shortStart;
          shortStart = previous.shortEnd;
          if (shortEnd - shortStart <= 0.05 || movieEnd - movieStart <= 0.05) continue;
        }

        // CONTINUITY MERGE
        if ((shortStart - previous.shortEnd).abs() <= 0.25 &&
            (movieStart - previous.movieEnd).abs() <= 0.25 &&
            movieEnd > previous.movieEnd) {
          previous.shortEnd = shortEnd;
          previous.movieEnd = movieEnd;
          continue;
        }
      }

      // Duplicate movie clip check
      if (isUnverifiedCandidate) {
        final isDuplicateMovieClip = segments.any(
          (s) =>
              ([0.0, [s.movieEnd, movieEnd].reduce((a, b) => a < b ? a : b) - [s.movieStart, movieStart].reduce((a, b) => a > b ? a : b)].reduce((a, b) => a > b ? a : b)) > 0.5 ||
              ((s.movieStart - movieStart).abs() < 0.5 && (s.movieEnd - movieEnd).abs() < 0.5),
        );
        if (isDuplicateMovieClip) continue;
      }

      final isConfirmed = match.verified == true || match.batchVerified == 'confirmed';
      segments.add(RenderSegment(
        movieStart: movieStart,
        movieEnd: movieEnd,
        shortStart: shortStart,
        shortEnd: shortEnd,
        origin: match.origin ?? 'chunk',
        originWindow: match.originWindow,
        rejected: match.rejected == true && match.userPick != true ? true : null,
        unverified: !isConfirmed && match.rejected != true ? true : null,
      ));
    }

    return segments;
  }

  static double totalStitchedSeconds(List<RenderSegment> segments) {
    return segments.fold(0.0, (sum, s) => sum + [0.0, s.movieEnd - s.movieStart].reduce((a, b) => a > b ? a : b));
  }

  /// Snap duration to frame grid
  static Map<String, dynamic> snapFrames(double dur, int fps) {
    final frames = [1, ([0.0, dur].reduce((a, b) => a > b ? a : b) * fps).round()].reduce((a, b) => a > b ? a : b);
    return {'frames': frames, 'snapDur': frames / fps};
  }

  /// Snap segments to frame grid
  static List<SnappedSegment> snapSegments(List<RenderSegment> segments, int fps) {
    return segments.map((seg) {
      final movieStart = [0.0, (seg.movieStart * fps).round() / fps].reduce((a, b) => a > b ? a : b);
      final snapped = snapFrames(seg.movieEnd - seg.movieStart, fps);
      final frames = snapped['frames'] as int;
      final snapDur = snapped['snapDur'] as double;
      return SnappedSegment(
        movieStart: movieStart,
        movieEnd: movieStart + snapDur,
        shortStart: seg.shortStart,
        shortEnd: seg.shortEnd,
        origin: seg.origin,
        originWindow: seg.originWindow,
        rejected: seg.rejected,
        unverified: seg.unverified,
        frames: frames,
        snapDur: snapDur,
      );
    }).toList();
  }

  static double totalSnappedSeconds(List<SnappedSegment> segments, int fps) {
    final totalFrames = segments.fold(0, (sum, s) => sum + s.frames);
    return totalFrames / fps;
  }
}
