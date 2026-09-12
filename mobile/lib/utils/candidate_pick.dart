import '../models/chunk.dart';
import '../models/scan.dart';

/// Pure helper functions for segment overlap logic and candidate selection.
/// 1:1 port of lib/candidate-pick.ts

/// Two short time windows are the same logical segment if:
/// 1. One is largely contained inside the other (±0.35s tolerance)
/// 2. They overlap by at least 20% of the shorter one (or >= 0.2s absolute)
/// 3. Their start or end times are within 0.45s of each other
bool sameShortSegment(double aStart, double aEnd, double bStart, double bEnd) {
  final aDur = (aEnd - aStart).abs();
  final bDur = (bEnd - bStart).abs();
  if (aDur < 0.05 || bDur < 0.05) return false;

  final oStart = aStart > bStart ? aStart : bStart;
  final oEnd = aEnd < bEnd ? aEnd : bEnd;
  final overlap = oEnd - oStart;

  // Case 1: Containment with small tolerance
  if (aStart >= bStart - 0.35 && aEnd <= bEnd + 0.35) return true;
  if (bStart >= aStart - 0.35 && bEnd <= aEnd + 0.35) return true;

  // Case 2: Significant overlap
  final minDur = aDur < bDur ? aDur : bDur;
  if (overlap > 0 && (overlap >= minDur * 0.2 || overlap >= 0.2)) return true;

  // Case 3: Start/end proximity
  if ((aStart - bStart).abs() < 0.45 || (aEnd - bEnd).abs() < 0.45) return true;

  return false;
}

String groupMatchOrigin(ChunkMatch match) {
  if (match.origin != null && match.origin!.isNotEmpty) return match.origin!;
  if (match.verified) return 'rescan';
  return 'chunk';
}

String originTag(String? origin) {
  if (origin == 'rescan') return ' [origin: rescan]';
  if (origin == 'gap-backup') return ' [origin: gap backup]';
  if (origin == 'user') return ' [origin: user pick]';
  return '';
}

CandidateEntry? bestRejectedCandidate(List<CandidateEntry> candidates) {
  // Prefer the latest rescan-found candidate, otherwise the highest ranked original
  final rescan = candidates
      .where((c) => c.source == 'rescan' && c.model != 'unknown')
      .toList();
  if (rescan.isNotEmpty) {
    rescan.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rescan.first;
  }
  final sorted = List<CandidateEntry>.from(candidates)
    ..sort((a, b) => (b.rank ?? 0).compareTo(a.rank ?? 0));
  return sorted.isNotEmpty ? sorted.first : null;
}

/// Applies candidate group selections to scan.matches in-place.
/// For each candidate group:
/// - If userPickId is set, that candidate becomes the active match.
/// - If confirmedMatchId is set, that candidate becomes the active match.
/// - If state is rejected_kept, the best available candidate stays in matches (flagged as rejected-kept).
/// - If undecided, pick the best candidate (user pick > confirmed > highest rank).
void applyGroupMatches(Scan scan) {
  final groups = scan.candidateGroups;
  if (groups.isEmpty) return;

  final resultMatches = <ChunkMatch>[];

  for (final group in groups) {
    CandidateEntry? chosen;

    if (group.userPickId != null && group.userPickId!.isNotEmpty) {
      chosen = group.candidates.where((c) => c.id == group.userPickId).firstOrNull;
    } else if (group.confirmedMatchId != null && group.confirmedMatchId!.isNotEmpty) {
      chosen = group.candidates.where((c) => c.id == group.confirmedMatchId).firstOrNull;
    } else if (group.state == 'rejected_kept') {
      chosen = bestRejectedCandidate(group.candidates);
    } else if (group.state == 'undecided' || group.state == 'confirmed') {
      // Find the best candidate: user pick > confirmed > highest rank
      final userPick = group.candidates.where((c) => c.userPick == true).firstOrNull;
      final confirmed = group.candidates.where((c) => c.batchVerified == 'confirmed' || c.verified == true).firstOrNull;
      final sorted = List<CandidateEntry>.from(group.candidates)
        ..sort((a, b) => (b.rank ?? 0).compareTo(a.rank ?? 0));
      chosen = userPick ?? confirmed ?? (sorted.isNotEmpty ? sorted.first : null);
    }

    if (chosen != null) {
      final isUserPick = group.userPickId == chosen.id || chosen.userPick == true;
      final isRejectedKept = group.state == 'rejected_kept';

      resultMatches.add(ChunkMatch(
        id: chosen.id,
        chunkIndex: chosen.chunkIndex,
        shortStart: chosen.shortStart,
        shortEnd: chosen.shortEnd,
        movieStart: chosen.movieStart,
        movieEnd: chosen.movieEnd,
        confidence: chosen.confidence ?? (chosen.verified ? 1.0 : 0.8),
        verified: chosen.verified || chosen.batchVerified == 'confirmed',
        model: chosen.model,
        reason: chosen.reason,
        origin: chosen.source,
        userPick: isUserPick ? true : null,
        batchVerified: chosen.batchVerified,
        batchVerifierReason: chosen.batchVerifierReason,
        batchCropPosition: chosen.batchCropPosition,
        batchProof: chosen.batchProof,
        rescanRequired: chosen.rescanRequired,
        rejectedKept: isRejectedKept ? true : null,
      ));
    }
  }

  // Deduplicate and sort chronologically
  resultMatches.sort((a, b) => a.shortStart.compareTo(b.shortStart));
  scan.matches = resultMatches;
}

class CandidateOption {
  final String id;
  final String label;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final String model;
  final double confidence;
  final String? reason;
  final String? batchVerifierReason;
  final String? batchCropPosition;
  final String? batchProof;
  final bool? rescanRequired;
  final String? source;
  final String? origin;
  final int? rank;
  final bool isMain;
  final String state; // 'confirmed' | 'rejected' | 'pending' | 'undecided'
  final bool isUserPick;
  final bool rejectedKept;

  CandidateOption({
    required this.id,
    required this.label,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.model,
    required this.confidence,
    this.reason,
    this.batchVerifierReason,
    this.batchCropPosition,
    this.batchProof,
    this.rescanRequired,
    this.source,
    this.origin,
    this.rank,
    required this.isMain,
    required this.state,
    required this.isUserPick,
    required this.rejectedKept,
  });
}

/// Returns a deduplicated list of candidate options for comparison / preview UI.
List<CandidateOption> candidateOptionsFor(
  CandidateGroup group,
  List<ChunkMatch> scanMatches,
  List<int>? chunkMinutes,
) {
  final activeMatchId = group.userPickId ?? group.confirmedMatchId;
  final seenMovieStarts = <int>{};
  final options = <CandidateOption>[];

  // Sort candidates: active first, then rescan, then by rank descending
  final sorted = List<CandidateEntry>.from(group.candidates)..sort((a, b) {
    if (a.id == activeMatchId) return -1;
    if (b.id == activeMatchId) return 1;
    if (a.source == 'rescan' && b.source != 'rescan') return -1;
    if (b.source == 'rescan' && a.source != 'rescan') return 1;
    return (b.rank ?? 0).compareTo(a.rank ?? 0);
  });

  for (final c in sorted) {
    // Deduplicate near-identical movie timestamps (within 0.5s)
    final key = (c.movieStart * 2).round();
    if (seenMovieStarts.contains(key) && c.id != activeMatchId) continue;
    seenMovieStarts.add(key);

    final isMain = c.id == activeMatchId || (activeMatchId == null && options.isEmpty);
    final isUserPick = group.userPickId == c.id || c.userPick == true;
    final isRejectedKept = group.state == 'rejected_kept' && isMain;

    String state = 'pending';
    if (c.batchVerified == 'confirmed' || c.verified) {
      state = 'confirmed';
    } else if (c.batchVerified == 'rejected') {
      state = 'rejected';
    } else if (group.state == 'undecided') {
      state = 'undecided';
    }

    final mmStart = (c.movieStart / 60).floor();
    final ssStart = (c.movieStart % 60).round().toString().padLeft(2, '0');
    final mmEnd = (c.movieEnd / 60).floor();
    final ssEnd = (c.movieEnd % 60).round().toString().padLeft(2, '0');
    final label = 'Movie $mmStart:$ssStart - $mmEnd:$ssEnd (chunk ${c.chunkIndex + 1})';

    options.add(CandidateOption(
      id: c.id,
      label: label,
      shortStart: c.shortStart,
      shortEnd: c.shortEnd,
      movieStart: c.movieStart,
      movieEnd: c.movieEnd,
      chunkIndex: c.chunkIndex,
      model: c.model,
      confidence: c.confidence ?? (c.verified ? 1.0 : 0.8),
      reason: c.reason,
      batchVerifierReason: c.batchVerifierReason,
      batchCropPosition: c.batchCropPosition,
      batchProof: c.batchProof,
      rescanRequired: c.rescanRequired,
      source: c.source,
      origin: c.source,
      rank: c.rank,
      isMain: isMain,
      state: state,
      isUserPick: isUserPick,
      rejectedKept: isRejectedKept,
    ));
  }

  return options;
}

bool hasAlternatives(CandidateGroup group) {
  return group.candidates.length > 1;
}

bool isUserPicked(CandidateGroup group) {
  return group.userPickId != null && group.userPickId!.isNotEmpty;
}

bool isRejectedKept(CandidateGroup group) {
  return group.state == 'rejected_kept';
}

String originLabel(String? origin) {
  if (origin == 'rescan') return 'Rescan (Gemini)';
  if (origin == 'gap-backup') return 'Missing-Scene Finder';
  if (origin == 'user') return 'User Manual Pick';
  return 'Chunk Scan';
}

class CandidatePickUtils {
  static bool sameShortSegment(double aStart, double aEnd, double bStart, double bEnd) =>
      sameShortSegment(aStart, aEnd, bStart, bEnd);

  static void applyGroupMatches(Scan scan, [CandidateGroup? g]) {
    if (g != null) {
      if (g.userPick is UserPick) {
        final up = g.userPick as UserPick;
        if (up.index >= 0 && up.index < g.candidates.length) {
          g.userPickId = g.candidates[up.index].id;
        }
      } else if (g.userPick == null) {
        g.userPickId = null;
      }
    }
    applyGroupMatches(scan);
  }
}
