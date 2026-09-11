import '../models/scan.dart';

/// 1:1 Port of lib/segment-range.ts
/// Client-safe helpers for the PER-MINUTE movie search range feature.

const int CHUNK_SECONDS = 60;

class SegmentRangeUtils {
  /// ABSOLUTE original-movie window of a chunk
  static Map<String, double> chunkAbsWindow(Scan scan, int chunkIndex) {
    final trimStart = scan.movieTrimStart ?? 0.0;
    final rangeEnd = scan.movieTrimEnd ?? scan.movieDuration ?? double.infinity;
    final start = trimStart + chunkIndex * CHUNK_SECONDS;
    return {
      'start': start,
      'end': [start + CHUNK_SECONDS, rangeEnd].reduce((a, b) => a < b ? a : b),
    };
  }

  /// Effective movie search range for one short minute
  static Map<String, dynamic> segMovieRange(Scan scan, ShortSegmentState seg) {
    final trimStart = scan.movieTrimStart ?? 0.0;
    final trimEnd = scan.movieTrimEnd ?? scan.movieDuration ?? double.infinity;
    final hasCustom = seg.movieRangeStart != null &&
        seg.movieRangeEnd != null &&
        seg.movieRangeEnd! > seg.movieRangeStart!;

    if (!hasCustom) return {'start': trimStart, 'end': trimEnd, 'custom': false};

    final start = [trimStart, seg.movieRangeStart!].reduce((a, b) => a > b ? a : b);
    final end = [trimEnd, seg.movieRangeEnd!].reduce((a, b) => a < b ? a : b);

    if (end <= start) return {'start': trimStart, 'end': trimEnd, 'custom': false};
    return {'start': start, 'end': end, 'custom': true};
  }

  /// True when the minute has an exact movie-minute allow-list (Minute Finder)
  static bool segHasMinuteList(ShortSegmentState seg) {
    return seg.movieMinutes != null && seg.movieMinutes!.isNotEmpty;
  }

  /// Compact "7-13, 21-24, 66" rendering of a sorted minute list
  static String formatMinuteList(List<int> minutes) {
    final sorted = minutes.toSet().toList()..sort();
    final parts = <String>[];
    int i = 0;
    while (i < sorted.length) {
      int j = i;
      while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
      i = j + 1;
    }
    return parts.join(', ');
  }

  /// True when a movie chunk overlaps the minute's chosen movie search range
  static bool chunkOverlapsSegRange(Scan scan, ShortSegmentState seg, int chunkIndex) {
    final w = chunkAbsWindow(scan, chunkIndex);
    if (segHasMinuteList(seg)) {
      final firstMin = (w['start']! / 60.0).floor();
      final lastMin = ([w['start']!, w['end']! - 0.001].reduce((a, b) => a > b ? a : b) / 60.0).floor();
      for (int m = firstMin; m <= lastMin; m++) {
        if (seg.movieMinutes!.contains(m)) return true;
      }
      return false;
    }
    final r = segMovieRange(scan, seg);
    return w['start']! < (r['end'] as double) && w['end']! > (r['start'] as double);
  }
}
