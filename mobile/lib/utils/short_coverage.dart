import '../models/scan.dart';

/// 1:1 Port of lib/short-coverage.ts
/// Pure helpers for Short video coverage calculations, gap analysis, and missing range recovery.

const double COVERAGE_MIN_GAP_SEC = 0.5;

class ShortRange {
  double start;
  double end;

  ShortRange({required this.start, required this.end});

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory ShortRange.fromJson(Map<String, dynamic> json) => ShortRange(
        start: (json['start'] as num?)?.toDouble() ?? 0.0,
        end: (json['end'] as num?)?.toDouble() ?? 0.0,
      );
}

class ShortCoverageData {
  final double coveredSec;
  final double totalSec;
  final double pct;
  final List<ShortRange> gaps;
  final double missingSec;
  final int at;

  ShortCoverageData({
    required this.coveredSec,
    required this.totalSec,
    required this.pct,
    required this.gaps,
    required this.missingSec,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'coveredSec': coveredSec,
        'totalSec': totalSec,
        'pct': pct,
        'gaps': gaps.map((g) => g.toJson()).toList(),
        'missingSec': missingSec,
        'at': at,
      };

  factory ShortCoverageData.fromJson(Map<String, dynamic> json) => ShortCoverageData(
        coveredSec: (json['coveredSec'] as num?)?.toDouble() ?? 0.0,
        totalSec: (json['totalSec'] as num?)?.toDouble() ?? 0.0,
        pct: (json['pct'] as num?)?.toDouble() ?? 0.0,
        gaps: (json['gaps'] as List<dynamic>?)?.map((g) => ShortRange.fromJson(g as Map<String, dynamic>)).toList() ?? [],
        missingSec: (json['missingSec'] as num?)?.toDouble() ?? 0.0,
        at: (json['at'] as num?)?.toInt() ?? 0,
      );
}

class ShortCoverageUtils {
  /// Union of ranges: sorted, overlapping/touching (<= touch s apart) ranges merged.
  static List<ShortRange> mergeRanges(List<ShortRange> rs, [double touch = 0.01]) {
    final s = rs.where((r) => r.end > r.start).toList()..sort((a, b) => a.start.compareTo(b.start));
    final out = <ShortRange>[];
    for (final r in s) {
      if (out.isNotEmpty && r.start <= out.last.end + touch) {
        out.last.end = [out.last.end, r.end].reduce((a, b) => a > b ? a : b);
      } else {
        out.add(ShortRange(start: r.start, end: r.end));
      }
    }
    return out;
  }

  /// [0, total) minus covered (which MUST already be merged/sorted).
  static List<ShortRange> gapsOf(List<ShortRange> covered, double total) {
    final gaps = <ShortRange>[];
    double cursor = 0.0;
    for (final c of covered) {
      if (c.start > cursor) {
        gaps.add(ShortRange(start: cursor, end: c.start));
      }
      cursor = [cursor, c.end].reduce((a, b) => a > b ? a : b);
    }
    if (cursor < total) {
      gaps.add(ShortRange(start: cursor, end: total));
    }
    return gaps;
  }

  /// Gaps = short minus coverage, each padded +-padSec, merged, and anything < minGapSec dropped.
  static List<ShortRange> missingRanges(
    List<ShortRange> covered,
    double shortDuration, {
    double padSec = 2.0,
    double minGapSec = 4.0,
    double? mergeWithinSec,
  }) {
    final merged = mergeRanges(covered);
    List<ShortRange> gaps = gapsOf(merged, shortDuration);
    if (mergeWithinSec != null) {
      gaps = mergeRanges(gaps, mergeWithinSec);
    }
    final padded = gaps.map((g) => ShortRange(
          start: [0.0, g.start - padSec].reduce((a, b) => a > b ? a : b),
          end: [shortDuration, g.end + padSec].reduce((a, b) => a < b ? a : b),
        )).toList();
    return mergeRanges(padded).where((g) => g.end - g.start >= minGapSec).toList();
  }

  /// Coverage of total seconds by the given short ranges
  static ShortCoverageData coverageFromRanges(List<ShortRange> ranges, double total) {
    final covered = mergeRanges(
      ranges.map((r) => ShortRange(
            start: [0.0, r.start].reduce((a, b) => a > b ? a : b),
            end: [total, r.end].reduce((a, b) => a < b ? a : b),
          )).toList(),
    );
    final gaps = gapsOf(covered, total).where((g) => g.end - g.start >= COVERAGE_MIN_GAP_SEC).toList();
    final missingSec = gaps.fold(0.0, (n, g) => n + (g.end - g.start));
    final coveredSec = [0.0, total - missingSec].reduce((a, b) => a > b ? a : b);
    final pct = total > 0 ? ((coveredSec / total) * 1000).round() / 10.0 : 0.0;
    return ShortCoverageData(
      coveredSec: coveredSec,
      totalSec: total,
      pct: pct,
      gaps: gaps,
      missingSec: missingSec,
      at: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Short duration to measure against
  static double shortTotalOf(Scan scan) {
    if (scan.shortDuration != null && scan.shortDuration! > 0) return scan.shortDuration!;
    return scan.matches.fold(0.0, (n, m) => [n, m.shortEnd].reduce((a, b) => a > b ? a : b));
  }

  /// Coverage of the short by ALL matches
  static ShortCoverageData computeShortCoverage(Scan scan) {
    final total = shortTotalOf(scan);
    final ranges = scan.matches.map((m) => ShortRange(start: m.shortStart, end: m.shortEnd)).toList();
    return coverageFromRanges(ranges, total);
  }

  /// mm:ss.mmm for coverage logs (short clock)
  static String fmtShortTs(double sec) {
    final s = [0.0, sec].reduce((a, b) => a > b ? a : b);
    final m = s ~/ 60;
    final r = s - m * 60;
    return '${m.toString().padLeft(2, '0')}:${r.toStringAsFixed(3).padLeft(6, '0')}';
  }
}
