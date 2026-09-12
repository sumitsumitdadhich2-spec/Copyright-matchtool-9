import 'dart:async';
import '../models/scan.dart';
import 'storage_service.dart';
import 'scheduler_service.dart';

/// 1:1 Port of lib/background-queue.ts
/// Background Scan Queue and Fair-Share Multi-Worker Scheduler.

class QueueEntry {
  final String scanId;
  final String owner;
  final int enqueuedAt;
  final Completer<void> completer;

  QueueEntry({
    required this.scanId,
    required this.owner,
    required this.enqueuedAt,
    required this.completer,
  });
}

class BackgroundQueueSnapshot {
  final int maxWorkers;
  final int activeWorkersCount;
  final List<String> activeScanIds;
  final int totalQueuedCount;
  final Map<String, int> queueByOwner;

  BackgroundQueueSnapshot({
    required this.maxWorkers,
    required this.activeWorkersCount,
    required this.activeScanIds,
    required this.totalQueuedCount,
    required this.queueByOwner,
  });
}

class BackgroundQueueService {
  static const int MAX_ACTIVE_WORKERS = 10;

  static final Set<String> _activeWorkers = {};
  static final Map<String, List<QueueEntry>> _ownerQueues = {};
  static final List<String> _ownerRoundRobin = [];
  static int _roundRobinPointer = 0;

  /// Snapshots current background queue state
  static BackgroundQueueSnapshot snapshot() {
    final Map<String, int> counts = {};
    int totalQueued = 0;

    for (final entry in _ownerQueues.entries) {
      counts[entry.key] = entry.value.length;
      totalQueued += entry.value.length;
    }

    return BackgroundQueueSnapshot(
      maxWorkers: MAX_ACTIVE_WORKERS,
      activeWorkersCount: _activeWorkers.length,
      activeScanIds: _activeWorkers.toList(),
      totalQueuedCount: totalQueued,
      queueByOwner: counts,
    );
  }

  /// Checks if a scan is currently active in the background worker pool
  static bool isActive(String scanId) => _activeWorkers.contains(scanId);

  /// Waits for a free background execution slot according to fair-share queueing
  static Future<void> acquireWorkerSlot(String scanId, {String owner = 'default'}) async {
    if (_activeWorkers.contains(scanId)) {
      return; // Already running in active slot
    }

    if (_activeWorkers.length < MAX_ACTIVE_WORKERS) {
      _activeWorkers.add(scanId);
      return;
    }

    final completer = Completer<void>();
    final entry = QueueEntry(
      scanId: scanId,
      owner: owner,
      enqueuedAt: DateTime.now().millisecondsSinceEpoch,
      completer: completer,
    );

    if (!_ownerQueues.containsKey(owner)) {
      _ownerQueues[owner] = [];
      _ownerRoundRobin.add(owner);
    }
    _ownerQueues[owner]!.add(entry);

    return completer.future;
  }

  /// Releases the worker slot for a completed/stopped scan and pumps the queue
  static void releaseWorkerSlot(String scanId) {
    _activeWorkers.remove(scanId);
    _pump();
  }

  /// Removes a scan from any waiting queues if cancelled prior to running
  static void removeWaitingScan(String scanId) {
    for (final queue in _ownerQueues.values) {
      queue.removeWhere((entry) {
        if (entry.scanId == scanId) {
          if (!entry.completer.isCompleted) {
            entry.completer.completeError(Exception('Scan queue cancelled'));
          }
          return true;
        }
        return false;
      });
    }
    _pump();
  }

  /// Pumps waiting jobs in fair round-robin order across owners
  static void _pump() {
    if (_activeWorkers.length >= MAX_ACTIVE_WORKERS) return;

    // Filter owners with active waiting jobs
    final activeOwners = _ownerRoundRobin.where((o) => (_ownerQueues[o]?.isNotEmpty ?? false)).toList();
    if (activeOwners.isEmpty) return;

    _roundRobinPointer = _roundRobinPointer % activeOwners.length;
    final currentOwner = activeOwners[_roundRobinPointer];
    _roundRobinPointer = (_roundRobinPointer + 1) % activeOwners.length;

    final nextEntry = _ownerQueues[currentOwner]!.removeAt(0);
    _activeWorkers.add(nextEntry.scanId);

    if (!nextEntry.completer.isCompleted) {
      nextEntry.completer.complete();
    }
  }

  static const int MAX_BACKGROUND_SCANS_PER_USER = 10;
  static bool _recoveryStarted = false;

  static int backgroundWorkerCount() => _activeWorkers.length;

  static Future<void> ensureBackgroundWorkers({StorageService? storageService}) async {
    if (!_recoveryStarted) {
      _recoveryStarted = true;
      if (storageService != null) {
        final scans = await storageService.loadScans();
        for (final s in scans) {
          if (s.background?.state == 'running' && !SchedulerService.isRunning(s.id)) {
            s.background = BackgroundInfo(
              state: 'queued',
              enqueuedAt: s.background?.enqueuedAt ?? DateTime.now().millisecondsSinceEpoch,
              resume: true,
            );
            await storageService.updateScan(s);
          }
        }
      }
    }
    _pump();
  }

  static Future<Map<String, dynamic>> enqueueBackgroundScan({
    required StorageService storageService,
    required String scanId,
    required String username,
    bool resume = false,
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null) return {'ok': false, 'error': 'Scan not found'};
    final current = scans.where((s) => s.ownerUsername == username && (s.background?.state == 'queued' || s.background?.state == 'running')).toList();
    if (scan.ownerUsername != null && scan.ownerUsername!.isNotEmpty && scan.ownerUsername != username) {
      return {'ok': false, 'error': 'This scan belongs to another user.'};
    }
    if (_activeWorkers.contains(scanId) || SchedulerService.isRunning(scanId)) {
      return {'ok': false, 'error': 'Scan is already running.'};
    }
    if (scan.background?.state == 'queued') {
      return {'ok': false, 'error': 'Scan is already queued.'};
    }
    final isQueued = scan.background?.state == 'queued' || scan.background?.state == 'running';
    if (current.length >= MAX_BACKGROUND_SCANS_PER_USER && !isQueued) {
      return {'ok': false, 'error': 'Maximum $MAX_BACKGROUND_SCANS_PER_USER background scans per user reached. Wait for one to finish.'};
    }

    scan.ownerUsername = username;
    scan.background = BackgroundInfo(
      state: 'queued',
      enqueuedAt: DateTime.now().millisecondsSinceEpoch,
      resume: resume,
    );
    await storageService.updateScan(scan);
    await ensureBackgroundWorkers(storageService: storageService);
    return {'ok': true};
  }

  static Future<bool> stopBackgroundScan(String scanId, {StorageService? storageService}) async {
    if (storageService != null) {
      final scans = await storageService.loadScans();
      final scan = scans.where((s) => s.id == scanId).firstOrNull;
      if (scan?.background?.state != 'queued') return false;
      if (_activeWorkers.contains(scanId)) return false;
      scan!.background = BackgroundInfo(
        state: 'stopped',
        enqueuedAt: scan.background?.enqueuedAt ?? DateTime.now().millisecondsSinceEpoch,
      );
      await storageService.updateScan(scan);
      removeWaitingScan(scanId);
      return true;
    }
    removeWaitingScan(scanId);
    return true;
  }
}
