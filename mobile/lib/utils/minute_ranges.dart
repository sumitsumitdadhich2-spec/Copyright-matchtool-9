import '../models/scan.dart';

/// 1:1 Port of lib/minute-ranges.ts
/// Shared helper to map approved MOVIE minutes back onto each SHORT minute.

class ApplyApprovedResult {
  final bool ok;
  final List<String>? rangeNotes;
  final String? error;

  ApplyApprovedResult.success(this.rangeNotes) : ok = true, error = null;
  ApplyApprovedResult.failure(this.error) : ok = false, rangeNotes = null;
}

String formatMinuteList(List<int> minutes) {
  if (minutes.isEmpty) return 'none';
  final sorted = List<int>.from(minutes)..sort();
  final ranges = <String>[];
  int? start;
  int? prev;

  for (final m in sorted) {
    if (start == null) {
      start = m;
      prev = m;
    } else if (m == prev! + 1) {
      prev = m;
    } else {
      ranges.add(start == prev ? '$start' : '$start-$prev');
      start = m;
      prev = m;
    }
  }
  if (start != null && prev != null) {
    ranges.add(start == prev ? '$start' : '$start-$prev');
  }
  return ranges.join(', ');
}

/// Maps approved MOVIE minutes back onto each SHORT minute via short windows overlap.
ApplyApprovedResult applyApprovedMinutes(
  Scan scan,
  List<int> approved,
  List<MinuteSuggestion> suggestions,
) {
  final segs = scan.shortSegments;
  if (segs.isEmpty) {
    return ApplyApprovedResult.failure('Short video segments missing');
  }
  if (approved.isEmpty) {
    return ApplyApprovedResult.failure('Kam se kam ek suggested minute approve karo.');
  }

  final approvedSet = approved.toSet();
  final trimStart = scan.movieTrimStart ?? 0.0;
  final trimEnd = scan.movieTrimEnd ?? scan.movieDuration ?? 0.0;
  final rangeNotes = <String>[];

  for (final seg in segs) {
    final relevantMinutes = <int>[];
    for (final sug in suggestions) {
      if (!approvedSet.contains(sug.minute)) continue;
      final overlaps = sug.shortWindows.any((w) => w.start < seg.end && w.end > seg.start);
      if (overlaps) relevantMinutes.add(sug.minute);
    }

    if (relevantMinutes.isEmpty) {
      seg.selected = false;
      seg.movieRangeStart = null;
      seg.movieRangeEnd = null;
      seg.movieMinutes = null;
      continue;
    }

    seg.selected = true;
    final minuteList = relevantMinutes.toSet().toList()..sort();
    seg.movieMinutes = minuteList;

    final rawStart = (minuteList.reduce((a, b) => a < b ? a : b)) * 60.0;
    final rawEnd = ((minuteList.reduce((a, b) => a > b ? a : b)) + 1) * 60.0;
    final start = rawStart < trimStart ? trimStart : rawStart;
    final end = rawEnd > trimEnd ? trimEnd : rawEnd;

    if (end > start && !(start <= trimStart && end >= trimEnd)) {
      seg.movieRangeStart = start;
      seg.movieRangeEnd = end;
    } else {
      seg.movieRangeStart = null;
      seg.movieRangeEnd = null;
    }

    rangeNotes.add('minute ${seg.index + 1} → movie minutes [${formatMinuteList(minuteList)}] (${minuteList.length} chunks)');
  }

  if (!segs.any((s) => s.selected != false)) {
    return ApplyApprovedResult.failure('Approved minutes kisi short minute se map nahi hue — Retry ya manual Full scan use karo.');
  }

  return ApplyApprovedResult.success(rangeNotes);
}
