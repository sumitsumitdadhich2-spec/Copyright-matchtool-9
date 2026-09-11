import 'dart:convert';
import 'dart:io';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../utils/candidate_pick.dart';
import '../utils/batch_verifier_prompt.dart';
import 'batch_minute_stitcher.dart';
import 'gemini_service.dart';
import 'storage_service.dart';

/// 1:1 Port of lib/batch-verifier-service.ts
/// Orchestrates the Gemini batch verification process (stitching -> Gemini analysis -> parsing -> match updates).

class BatchVerdict {
  final int partIndex;
  final String verdict; // 'CONFIRMED' | 'REJECTED'
  final double confidence;
  final String? cropPosition;
  final String? visualAnchorProof;
  final String? reason;
  final bool rescanRequired;

  BatchVerdict({
    required this.partIndex,
    required this.verdict,
    required this.confidence,
    this.cropPosition,
    this.visualAnchorProof,
    this.reason,
    this.rescanRequired = false,
  });
}

class BatchVerifierService {
  static final Map<String, bool> _activeCancelTokens = {};

  static const List<String> VERIFIER_MODELS = [
    'gemini-3.7-flash',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
  ];

  static bool isRunning(String scanId) => _activeCancelTokens[scanId] == false;

  static void stopVerification(String scanId) {
    if (_activeCancelTokens.containsKey(scanId)) {
      _activeCancelTokens[scanId] = true;
    }
  }

  /// Parses the raw JSON response from Gemini batch verifier
  static List<BatchVerdict> parseBatchVerifierResponse(
    String rawText,
    List<BatchVerifyPart> parts,
  ) {
    final results = <BatchVerdict>[];

    try {
      // 1. Clean markdown JSON fences
      String clean = rawText.trim();
      if (clean.contains('```json')) {
        clean = clean.split('```json')[1].split('```')[0].trim();
      } else if (clean.contains('```')) {
        clean = clean.split('```')[1].split('```')[0].trim();
      }

      // Remove trailing commas before closing braces/brackets
      clean = clean.replaceAll(RegExp(r',\s*([\]\}])'), r'$1');

      final dynamic parsed = jsonDecode(clean);
      final List<dynamic> verdictsList = (parsed is Map && parsed.containsKey('verdicts'))
          ? (parsed['verdicts'] as List<dynamic>)
          : (parsed is List ? parsed : []);

      for (final item in verdictsList) {
        if (item is Map) {
          final pIdx = int.tryParse(item['partIndex']?.toString() ?? '') ?? 0;
          final vStr = (item['verdict']?.toString() ?? 'REJECTED').toUpperCase().trim();
          final isConfirmed = vStr.contains('CONFIRM');
          final conf = double.tryParse(item['confidence']?.toString() ?? '') ?? (isConfirmed ? 0.95 : 0.2);

          results.add(BatchVerdict(
            partIndex: pIdx,
            verdict: (isConfirmed && conf >= 0.75) ? 'CONFIRMED' : 'REJECTED',
            confidence: conf,
            cropPosition: item['cropPosition']?.toString(),
            visualAnchorProof: item['visualAnchorProof']?.toString(),
            reason: item['reason']?.toString(),
            rescanRequired: item['rescanRequired'] == true || !isConfirmed,
          ));
        }
      }
    } catch (_) {
      // Fallback regex parser if JSON decoding failed
      final partMatches = RegExp(r'\{[^{}]*"partIndex"\s*:\s*(\d+)[^{}]*\}', dotAll: true).allMatches(rawText);
      for (final pm in partMatches) {
        final block = pm.group(0)!;
        final pIdxMatch = RegExp(r'"partIndex"\s*:\s*(\d+)').firstMatch(block);
        final vMatch = RegExp(r'"verdict"\s*:\s*"([^"]+)"').firstMatch(block);
        final confMatch = RegExp(r'"confidence"\s*:\s*([0-9.]+)').firstMatch(block);
        final cropMatch = RegExp(r'"cropPosition"\s*:\s*"([^"]+)"').firstMatch(block);
        final proofMatch = RegExp(r'"visualAnchorProof"\s*:\s*"([^"]+)"').firstMatch(block);
        final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]+)"').firstMatch(block);

        if (pIdxMatch != null) {
          final pIdx = int.parse(pIdxMatch.group(1)!);
          final vStr = (vMatch?.group(1) ?? 'REJECTED').toUpperCase();
          final isConfirmed = vStr.contains('CONFIRM');
          final conf = double.tryParse(confMatch?.group(1) ?? '') ?? (isConfirmed ? 0.95 : 0.2);

          results.add(BatchVerdict(
            partIndex: pIdx,
            verdict: (isConfirmed && conf >= 0.75) ? 'CONFIRMED' : 'REJECTED',
            confidence: conf,
            cropPosition: cropMatch?.group(1),
            visualAnchorProof: proofMatch?.group(1),
            reason: reasonMatch?.group(1),
            rescanRequired: !isConfirmed,
          ));
        }
      }
    }

    return results;
  }

  /// Verifies a single 1-minute window
  static Future<void> verifySingleMinute({
    required Scan scan,
    required GeminiService geminiService,
    required StorageService storageService,
    required int minuteIndex,
    required String shortPath,
    required String moviePath,
    required String outputDir,
    required Function(String log) onLog,
  }) async {
    final minutePlans = BatchMinuteStitcher.planMinuteSegments(
      matches: scan.matches,
      candidateGroups: scan.candidateGroups,
      shortDuration: scan.shortDuration ?? 0,
      movieTrimStart: scan.movieTrimStart ?? 0,
      movieTrimEnd: scan.movieTrimEnd,
      movieDuration: scan.movieDuration,
    );

    if (minuteIndex >= minutePlans.length) return;
    final parts = minutePlans[minuteIndex];
    if (parts.isEmpty) {
      onLog('Minute ${minuteIndex + 1}: No verification candidates present.');
      return;
    }

    onLog('Minute ${minuteIndex + 1}: Stitching ${parts.length} candidate verification parts (24 FPS CFR)...');

    final stitched = await BatchMinuteStitcher.stitchMinuteVerificationClips(
      shortPath: shortPath,
      moviePath: moviePath,
      parts: parts,
      outputDir: outputDir,
      minuteIndex: minuteIndex,
    );

    if (stitched == null) return;

    try {
      onLog('Minute ${minuteIndex + 1}: Uploading stitched Short & Movie clips to Gemini...');
      final shortFileUri = await geminiService.uploadVideoFile(stitched.shortStitchedPath);
      final movieFileUri = await geminiService.uploadVideoFile(stitched.movieStitchedPath);

      final prompt = buildBatchVerifierPrompt(parts.map((p) => p.toSpec()).toList());

      onLog('Minute ${minuteIndex + 1}: Running forensic verification with Gemini Flash...');
      final responseText = await geminiService.generateContentWithTwoVideos(
        videoUri1: shortFileUri,
        videoUri2: movieFileUri,
        prompt: prompt,
        model: VERIFIER_MODELS.first,
      );

      final verdicts = parseBatchVerifierResponse(responseText, parts);
      onLog('Minute ${minuteIndex + 1}: Received ${verdicts.length} verdicts from auditor.');

      // Apply verdicts to matches & candidate groups
      for (final verdict in verdicts) {
        final part = parts.where((p) => p.index == verdict.partIndex).firstOrNull;
        if (part == null) continue;

        final isConfirmed = verdict.verdict == 'CONFIRMED';

        // 1. Update CandidateGroups
        for (final group in scan.candidateGroups) {
          if (sameShortSegment(group.shortStart, group.shortEnd, part.shortStart, part.shortEnd)) {
            final targetCandidate = group.candidates.where((c) =>
                c.id == part.candidateId ||
                ((c.movieStart - part.movieStart).abs() < 0.5 && c.chunkIndex == part.chunkIndex)).firstOrNull;

            if (targetCandidate != null) {
              targetCandidate.batchVerified = isConfirmed ? 'confirmed' : 'rejected';
              targetCandidate.confidence = verdict.confidence;
              targetCandidate.batchVerifierReason = verdict.reason;
              targetCandidate.batchCropPosition = verdict.cropPosition;
              targetCandidate.batchProof = verdict.visualAnchorProof;
              targetCandidate.rescanRequired = verdict.rescanRequired;

              if (isConfirmed) {
                targetCandidate.verified = true;
                group.confirmedMatchId = targetCandidate.id;
                group.state = 'confirmed';
              } else if (group.confirmedMatchId == targetCandidate.id) {
                group.confirmedMatchId = null;
                group.state = group.candidates.any((c) => c.batchVerified != 'rejected') ? 'undecided' : 'rejected';
              }
            }
          }
        }

        // 2. Update Active Matches
        for (final match in scan.matches) {
          if (match.id == part.matchId ||
              ((match.shortStart - part.shortStart).abs() < 0.35 && (match.movieStart - part.movieStart).abs() < 0.5)) {
            match.batchVerified = isConfirmed ? 'confirmed' : 'rejected';
            match.batchVerifierReason = verdict.reason;
            match.batchCropPosition = verdict.cropPosition;
            match.batchProof = verdict.visualAnchorProof;
            match.rescanRequired = verdict.rescanRequired;
            if (isConfirmed) {
              match.verified = true;
              match.confidence = verdict.confidence;
            }
          }
        }
      }

      // Re-apply group matches to guarantee non-overlapping pristine results
      applyGroupMatches(scan);
      await storageService.saveScan(scan);
      onLog('Minute ${minuteIndex + 1}: Batch verification successfully applied.');
    } finally {
      // Clean up stitched video files
      try {
        final f1 = File(stitched.shortStitchedPath);
        if (await f1.exists()) await f1.delete();
        final f2 = File(stitched.movieStitchedPath);
        if (await f2.exists()) await f2.delete();
      } catch (_) {}
    }
  }

  /// Runs batch verification across all 1-minute segments
  static Future<void> startBatchVerificationAll({
    required Scan scan,
    required GeminiService geminiService,
    required StorageService storageService,
    required String shortPath,
    required String moviePath,
    required String outputDir,
    required Function(String log) onLog,
  }) async {
    _activeCancelTokens[scan.id] = false;

    try {
      final minutePlans = BatchMinuteStitcher.planMinuteSegments(
        matches: scan.matches,
        candidateGroups: scan.candidateGroups,
        shortDuration: scan.shortDuration ?? 0,
        movieTrimStart: scan.movieTrimStart ?? 0,
        movieTrimEnd: scan.movieTrimEnd,
        movieDuration: scan.movieDuration,
      );

      onLog('Starting Forensic Batch Verification across ${minutePlans.length} minute segment(s)...');

      for (int i = 0; i < minutePlans.length; i++) {
        if (_activeCancelTokens[scan.id] == true) {
          onLog('Batch verification stopped by user.');
          break;
        }

        if (minutePlans[i].isEmpty) continue;

        await verifySingleMinute(
          scan: scan,
          geminiService: geminiService,
          storageService: storageService,
          minuteIndex: i,
          shortPath: shortPath,
          moviePath: moviePath,
          outputDir: outputDir,
          onLog: onLog,
        );
      }

      onLog('All batch verification operations complete.');
    } finally {
      _activeCancelTokens.remove(scan.id);
    }
  }
}
