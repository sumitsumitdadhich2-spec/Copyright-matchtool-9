import '../models/scan.dart';
import '../services/storage_service.dart';
import '../services/session_service.dart';
import '../services/render_service.dart';
import '../services/scheduler_service.dart';
import '../services/batch_verifier_service.dart';
import '../services/store_service.dart';
import '../utils/candidate_pick.dart';
import '../utils/formatters.dart';

/// 1:1 Port of app/api/scans/[id]/batch-verify & app/api/scans/[id]/candidates/pick

class ScanApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;

  ScanApiResponse({required this.statusCode, required this.data});
}

class ScanActionsApi {
  static bool _canAccess(SessionUser session, Scan scan) {
    return session.role == 'admin' || scan.ownerUsername == session.username;
  }

  // =========================================================================
  // BATCH VERIFY: GET & POST /api/scans/[id]/batch-verify
  // =========================================================================

  static Future<ScanApiResponse> getBatchVerify({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    final state = BatchVerifierService.getOrCreateBatchVerifyState(scan);
    return ScanApiResponse(
      statusCode: 200,
      data: {
        'batchVerify': state,
        'matchCount': scan.matches.length,
        'shortDuration': scan.shortDuration ?? 0.0,
      },
    );
  }

  static Future<ScanApiResponse> postBatchVerify({
    required StorageService storageService,
    required BatchVerifierService batchVerifierService,
    required String? sessionToken,
    required String scanId,
    String? action,
    int? minuteIndex,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Scan not found'});
    }

    if (action == 'stop') {
      batchVerifierService.stopBatchVerification(scanId);
      return ScanApiResponse(statusCode: 200, data: {'ok': true, 'message': 'Batch verification stopped'});
    }

    if (action == 'verify_minute' && minuteIndex != null) {
      // Run single minute
      batchVerifierService.verifySingleMinute(scanId, minuteIndex);
      return ScanApiResponse(
        statusCode: 200,
        data: {'ok': true, 'message': 'Verification started for minute ${minuteIndex + 1}'},
      );
    }

    // Default: start all minutes
    batchVerifierService.startBatchVerificationAll(scanId);
    return ScanApiResponse(
      statusCode: 200,
      data: {'ok': true, 'message': 'All-in-one batch verification started'},
    );
  }

  // =========================================================================
  // CANDIDATES PICK: POST /api/scans/[id]/candidates/pick
  // =========================================================================

  static Future<ScanApiResponse> pickCandidate({
    required StorageService storageService,
    required String? sessionToken,
    required String scanId,
    String? groupId,
    dynamic candidateIndex, // int or null
    bool? viaRescan,
    double? shortStart,
    double? shortEnd,
    double? movieStart,
    double? movieEnd,
    int? chunkIndex,
    String? model,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) return ScanApiResponse(statusCode: 401, data: {'error': 'Unauthorized'});

    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !_canAccess(session, scan)) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Not found'});
    }

    if (RenderService.isRenderActive(scanId) || scan.renderJob?.status == 'rendering') {
      return ScanApiResponse(
        statusCode: 409,
        data: {'error': 'Render chal raha hai — finish ya cancel hone ke baad main clip badlo'},
      );
    }

    CandidateGroup? g = scan.candidateGroups.where((x) => x.id == groupId).firstOrNull;
    if (g == null && shortStart != null && shortEnd != null) {
      g = scan.candidateGroups.where((x) => CandidatePickUtils.sameShortSegment(x.shortStart, x.shortEnd, shortStart, shortEnd)).firstOrNull;
    }
    if (g == null) {
      return ScanApiResponse(statusCode: 404, data: {'error': 'Candidate group not found'});
    }

    if (candidateIndex == null) {
      g.userPick = null;
      CandidatePickUtils.applyGroupMatches(scan, g);
      StoreService.addLog(
        scan,
        LogLevel.info,
        'User choice cleared for short ${fmtTime(g.shortStart)}–${fmtTime(g.shortEnd)} — AI verdict (${g.status}) restored',
      );
    } else {
      int idx = (candidateIndex as num).toInt();
      if (idx < 0 || idx >= g.candidates.length) {
        if (movieStart != null && movieEnd != null) {
          final found = g.candidates.indexWhere(
            (c) => (c.movieStart - movieStart).abs() < 0.5 && (c.movieEnd - movieEnd).abs() < 0.5,
          );
          if (found >= 0) {
            idx = found;
          } else {
            idx = g.candidates.length;
            g.candidates.add(Candidate(
              shortStart: shortStart ?? g.shortStart,
              shortEnd: shortEnd ?? g.shortEnd,
              movieStart: movieStart,
              movieEnd: movieEnd,
              chunkIndex: chunkIndex ?? 0,
              model: model ?? 'gemini-3.7-flash',
              verdict: 'same',
              rescan: 'none',
            ));
          }
        } else {
          return ScanApiResponse(statusCode: 400, data: {'error': 'Invalid candidate index'});
        }
      }

      final c = g.candidates[idx];
      final isViaRescan = viaRescan == true;
      if (isViaRescan && (c.rescanMovieStart == null || c.rescanMovieEnd == null)) {
        return ScanApiResponse(statusCode: 400, data: {'error': 'This candidate has no rescan window'});
      }

      g.userPick = UserPick(index: idx, viaRescan: isViaRescan, at: DateTime.now().millisecondsSinceEpoch);
      CandidatePickUtils.applyGroupMatches(scan, g);

      final ms = isViaRescan ? c.rescanMovieStart! : c.movieStart;
      final me = isViaRescan ? c.rescanMovieEnd! : c.movieEnd;

      StoreService.addLog(
        scan,
        LogLevel.success,
        'USER CHOICE: short ${fmtTime(g.shortStart)}–${fmtTime(g.shortEnd)} → movie ${fmtTime(ms)}–${fmtTime(me)} (candidate #${idx + 1}${isViaRescan ? ', rescan window' : ''}, chunk ${c.chunkIndex}) set as MAIN clip — AI verdict was ${g.status}. Preview + export input updated.',
      );
    }

    if (scan.report != null) {
      scan.report!.matches = scan.matches;
    }

    await storageService.updateScan(scan);
    return ScanApiResponse(statusCode: 200, data: {'ok': true, 'matches': scan.matches.length});
  }
}
