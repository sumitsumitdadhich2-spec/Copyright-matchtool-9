import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 1:1 Port of lib/global-gemini-coordinator.ts
/// Global Gemini Coordinator for cross-scan pacing, 429 rate limit cooldowns, and lane exclusivity.

class CandidateLane {
  final String apiKey;
  final int keyIdx;
  final String modelId;
  final int slot;
  final int? rpd;

  CandidateLane({
    required this.apiKey,
    this.keyIdx = 1,
    required this.modelId,
    this.slot = 0,
    this.rpd,
  });
}

class LaneWaiter {
  final String scanId;
  final String scanTitle;
  final String operation;
  final Function(Function([double? actualVideoSec]) releaseFn) resolve;
  final Function(Object err) reject;
  final bool Function()? isStopping;

  LaneWaiter({
    required this.scanId,
    required this.scanTitle,
    required this.operation,
    required this.resolve,
    required this.reject,
    this.isStopping,
  });
}

class GlobalLaneState {
  final String laneKey;
  final String keyHash;
  int keyIdx;
  final String modelId;
  final int slot;
  String? activeScanId;
  String? activeScanTitle;
  String? activeOperation;
  int? activeSince;
  int nextFreeAt;
  int cooldownUntil;
  bool isExhausted;
  final List<LaneWaiter> waiters;

  GlobalLaneState({
    required this.laneKey,
    required this.keyHash,
    required this.keyIdx,
    required this.modelId,
    required this.slot,
    this.activeScanId,
    this.activeScanTitle,
    this.activeOperation,
    this.activeSince,
    this.nextFreeAt = 0,
    this.cooldownUntil = 0,
    this.isExhausted = false,
    List<LaneWaiter>? waiters,
  }) : waiters = waiters ?? [];
}

String hashApiKey(String key) {
  return sha256.convert(utf8.encode(key)).toString().substring(0, 12);
}

class GlobalGeminiCoordinator {
  static final GlobalGeminiCoordinator instance = GlobalGeminiCoordinator._internal();
  GlobalGeminiCoordinator._internal();

  static const int RATE_COOLDOWN_MS = 60000;

  final Map<String, GlobalLaneState> _lanes = {};

  String _getLaneKey(String apiKey, String modelId, [int slot = 0]) {
    return '${hashApiKey(apiKey)}:$modelId:$slot';
  }

  GlobalLaneState _getOrCreateLane(String apiKey, String modelId, [int slot = 0, int keyIdx = 1]) {
    final key = _getLaneKey(apiKey, modelId, slot);
    var lane = _lanes[key];
    if (lane == null) {
      lane = GlobalLaneState(
        laneKey: key,
        keyHash: hashApiKey(apiKey),
        keyIdx: keyIdx,
        modelId: modelId,
        slot: slot,
      );
      _lanes[key] = lane;
    }
    if (keyIdx > 0) lane.keyIdx = keyIdx;
    return lane;
  }

  static int pacingIntervalMs(double videoSeconds) {
    if (videoSeconds <= 60) return 4000;
    if (videoSeconds <= 180) return 6000;
    if (videoSeconds <= 600) return 12000;
    return 20000;
  }

  /// Check if a lane is currently in use by ANY scan or in cooldown/pacing
  Map<String, dynamic> isLaneBusy(String apiKey, String modelId, [int slot = 0]) {
    final lane = _getOrCreateLane(apiKey, modelId, slot);
    final now = DateTime.now().millisecondsSinceEpoch;

    if (lane.activeScanId != null) {
      return {
        'busy': true,
        'activeScanId': lane.activeScanId,
        'activeScanTitle': lane.activeScanTitle,
        'activeOperation': lane.activeOperation,
      };
    }

    if (lane.cooldownUntil > now) {
      return {
        'busy': true,
        'cooling': true,
        'waitSec': ((lane.cooldownUntil - now) / 1000).ceil(),
      };
    }

    if (lane.nextFreeAt > now) {
      return {
        'busy': true,
        'waitSec': ((lane.nextFreeAt - now) / 1000).ceil(),
      };
    }

    return {'busy': false};
  }

  /// Check if an API key has any active lanes currently executing in another scan
  bool isKeyActiveInOtherScan(String apiKey, String currentScanId) {
    final hash = hashApiKey(apiKey);
    for (final lane in _lanes.values) {
      if (lane.keyHash == hash && lane.activeScanId != null && lane.activeScanId != currentScanId) {
        return true;
      }
    }
    return false;
  }

  /// Acquire an exclusive lock on a (Key × Model × Slot) lane
  Future<Function([double? actualVideoSec])> acquireLane({
    required String scanId,
    String? scanTitle,
    required String apiKey,
    int keyIdx = 1,
    required String modelId,
    int slot = 0,
    required String operation,
    double videoSeconds = 60,
    Function(String msg, int waitSec)? onWait,
    bool Function()? isStopping,
  }) {
    final title = scanTitle ?? scanId;
    final lane = _getOrCreateLane(apiKey, modelId, slot, keyIdx);

    final completer = Completer<Function([double? actualVideoSec])>();

    void tryAcquireOrQueue() {
      if (isStopping != null && isStopping()) {
        completer.completeError(Exception('Stop requested — lane acquisition cancelled'));
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final hasOtherActive = lane.activeScanId != null;
      final isQueuedBehindOthers = lane.waiters.isNotEmpty && lane.waiters.first.scanId != scanId;

      if (hasOtherActive || isQueuedBehindOthers) {
        final waitMsg = hasOtherActive
            ? '[Global Coordinator] Key ${lane.keyIdx} · $modelId is busy in Scan "${lane.activeScanTitle ?? lane.activeScanId}" (${lane.activeOperation ?? "working"}). Waiting for lane...'
            : '[Global Coordinator] Key ${lane.keyIdx} · $modelId is queued behind other scans. Waiting turn...';

        onWait?.(waitMsg, 5);

        lane.waiters.add(LaneWaiter(
          scanId: scanId,
          scanTitle: title,
          operation: operation,
          resolve: (releaseFn) => completer.complete(releaseFn),
          reject: (err) => completer.completeError(err),
          isStopping: isStopping,
        ));
        return;
      }

      // 429 Cooldown
      if (lane.cooldownUntil > now) {
        final waitMs = lane.cooldownUntil - now;
        final waitSec = (waitMs / 1000).ceil();
        onWait?.(
          '[Global Coordinator] Key ${lane.keyIdx} · $modelId is in 429 rate cooldown (${waitSec}s remaining). Waiting for rate limit reset...',
          waitSec,
        );

        Timer(Duration(milliseconds: waitMs + 50), () {
          if (isStopping != null && isStopping()) {
            completer.completeError(Exception('Stop requested during cooldown'));
            return;
          }
          _processNext(lane);
        });

        lane.waiters.add(LaneWaiter(
          scanId: scanId,
          scanTitle: title,
          operation: operation,
          resolve: (releaseFn) => completer.complete(releaseFn),
          reject: (err) => completer.completeError(err),
          isStopping: isStopping,
        ));
        return;
      }

      // TPM Pacing wait
      if (lane.nextFreeAt > now) {
        final waitMs = lane.nextFreeAt - now;
        final waitSec = (waitMs / 1000).ceil();
        onWait?.(
          '[Global Coordinator] Key ${lane.keyIdx} · $modelId pacing wait (${waitSec}s for TPM quota). Pacing request...',
          waitSec,
        );

        Timer(Duration(milliseconds: waitMs + 20), () {
          if (isStopping != null && isStopping()) {
            completer.completeError(Exception('Stop requested during pacing wait'));
            return;
          }
          _processNext(lane);
        });

        lane.waiters.add(LaneWaiter(
          scanId: scanId,
          scanTitle: title,
          operation: operation,
          resolve: (releaseFn) => completer.complete(releaseFn),
          reject: (err) => completer.completeError(err),
          isStopping: isStopping,
        ));
        return;
      }

      // Lock is free!
      lane.activeScanId = scanId;
      lane.activeScanTitle = title;
      lane.activeOperation = operation;
      lane.activeSince = DateTime.now().millisecondsSinceEpoch;

      void releaseFn([double? actualVideoSec]) {
        _releaseLane(lane, actualVideoSec ?? videoSeconds);
      }

      completer.complete(releaseFn);
    }

    tryAcquireOrQueue();
    return completer.future;
  }

  /// Dynamically search across multiple candidate lanes and grab first available
  Future<Map<String, dynamic>> acquireFirstAvailableLane({
    required String scanId,
    String? scanTitle,
    required List<CandidateLane> candidates,
    required String operation,
    double videoSeconds = 60,
    Function(String msg, int waitSec, String candidateSummary)? onWait,
    bool Function()? isStopping,
  }) async {
    final title = scanTitle ?? scanId;
    if (candidates.isEmpty) {
      throw Exception('No candidate lanes provided for execution');
    }

    String lastLoggedWaitMsg = '';

    while (true) {
      if (isStopping != null && isStopping()) {
        throw Exception('Stop requested — lane acquisition cancelled');
      }

      final now = DateTime.now().millisecondsSinceEpoch;

      // Filter available candidates
      final availableCandidates = candidates.where((c) {
        final lane = _getOrCreateLane(c.apiKey, c.modelId, c.slot, c.keyIdx);
        return !lane.isExhausted;
      }).toList();

      if (availableCandidates.isEmpty) {
        throw Exception('All candidate keys/models have reached their daily quota or are exhausted');
      }

      // Check immediately free lanes
      for (final cand in availableCandidates) {
        final lane = _getOrCreateLane(cand.apiKey, cand.modelId, cand.slot, cand.keyIdx);
        final isFree = lane.activeScanId == null &&
            lane.cooldownUntil <= now &&
            lane.nextFreeAt <= now &&
            lane.waiters.isEmpty;

        if (isFree) {
          lane.activeScanId = scanId;
          lane.activeScanTitle = title;
          lane.activeOperation = operation;
          lane.activeSince = DateTime.now().millisecondsSinceEpoch;

          void release([double? actualVideoSec]) {
            _releaseLane(lane, actualVideoSec ?? videoSeconds);
          }

          return {'selected': cand, 'release': release};
        }
      }

      // Calculate shortest wait
      int shortestWait = 999999999;
      for (final c in availableCandidates) {
        final lane = _getOrCreateLane(c.apiKey, c.modelId, c.slot, c.keyIdx);
        final cdWait = (lane.cooldownUntil - now).clamp(0, 999999999);
        final paceWait = (lane.nextFreeAt - now).clamp(0, 999999999);
        final activeWait = lane.activeScanId != null ? 4000 : 0;
        final totalWait = [cdWait, paceWait, activeWait].reduce((a, b) => a > b ? a : b);
        if (totalWait < shortestWait) shortestWait = totalWait;
      }

      final waitSec = (shortestWait / 1000).ceil().clamp(1, 99999);
      final candidateSummary = availableCandidates.take(4).map((c) => 'Key ${c.keyIdx} (${c.modelId})').join(', ');
      final waitMsg = '[Global Coordinator] All candidate lanes busy ($candidateSummary). Re-checking every 1s (next free ~${waitSec}s)...';

      if (waitMsg != lastLoggedWaitMsg) {
        lastLoggedWaitMsg = waitMsg;
        onWait?.(waitMsg, waitSec, candidateSummary);
      }

      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _releaseLane(GlobalLaneState lane, double videoSeconds) {
    final paceMs = pacingIntervalMs(videoSeconds);
    final elapsedSinceActive = lane.activeSince != null
        ? (DateTime.now().millisecondsSinceEpoch - lane.activeSince!).clamp(0, 999999999)
        : 0;
    final remainingPaceMs = (paceMs - elapsedSinceActive).clamp(0, 999999999);
    lane.nextFreeAt = DateTime.now().millisecondsSinceEpoch + remainingPaceMs;
    lane.activeScanId = null;
    lane.activeScanTitle = null;
    lane.activeOperation = null;
    lane.activeSince = null;

    if (lane.waiters.isNotEmpty) {
      Timer(Duration(milliseconds: remainingPaceMs + 20), () {
        _processNext(lane);
      });
    }
  }

  void _processNext(GlobalLaneState lane) {
    if (lane.activeScanId != null) return;

    while (lane.waiters.isNotEmpty) {
      final next = lane.waiters.removeAt(0);

      if (next.isStopping != null && next.isStopping!()) {
        next.reject(Exception('Stop requested while queued'));
        continue;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (lane.cooldownUntil > now) {
        lane.waiters.insert(0, next);
        final waitMs = lane.cooldownUntil - now;
        Timer(Duration(milliseconds: waitMs + 50), () => _processNext(lane));
        return;
      }

      if (lane.nextFreeAt > now) {
        lane.waiters.insert(0, next);
        final waitMs = lane.nextFreeAt - now;
        Timer(Duration(milliseconds: waitMs + 20), () => _processNext(lane));
        return;
      }

      lane.activeScanId = next.scanId;
      lane.activeScanTitle = next.scanTitle;
      lane.activeOperation = next.operation;
      lane.activeSince = DateTime.now().millisecondsSinceEpoch;

      void releaseFn([double? actualVideoSec]) {
        _releaseLane(lane, actualVideoSec ?? 60);
      }

      next.resolve(releaseFn);
      return;
    }
  }

  void reportRateLimit(String apiKey, String modelId, [int cooldownMs = RATE_COOLDOWN_MS, int slot = 0]) {
    final kh = hashApiKey(apiKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final lane = _getOrCreateLane(apiKey, modelId, slot);
    lane.cooldownUntil = [lane.cooldownUntil, now + cooldownMs].reduce((a, b) => a > b ? a : b);

    for (final other in _lanes.values) {
      if (other.keyHash == kh && other.modelId == modelId) {
        other.cooldownUntil = [other.cooldownUntil, now + cooldownMs].reduce((a, b) => a > b ? a : b);
      } else if (other.keyHash == kh) {
        other.cooldownUntil = [other.cooldownUntil, now + 5000].reduce((a, b) => a > b ? a : b);
      }
    }
  }

  void reportExhausted(String apiKey, String modelId, [int slot = 0]) {
    final kh = hashApiKey(apiKey);
    final lane = _getOrCreateLane(apiKey, modelId, slot);
    lane.isExhausted = true;

    for (final other in _lanes.values) {
      if (other.keyHash == kh && other.modelId == modelId) {
        other.isExhausted = true;
      }
    }
  }
}
