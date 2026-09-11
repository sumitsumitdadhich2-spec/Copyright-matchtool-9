import '../models/scan.dart';
import 'storage_service.dart';
import 'ffmpeg_service.dart';
import 'gemini_service.dart';
import 'gemini_minute_finder_service.dart';
import 'merge_pipeline_service.dart';

/// 1:1 Port of lib/minute-finder-dispatch.ts
/// Single auto-trigger entry point after upload/trim confirmation.

class MinuteFinderDispatch {
  /// Dispatches the appropriate minute finder based on user mode ('gemini' | 'twelvelabs' | 'off')
  static Future<String?> dispatchMinuteFinder({
    required StorageService storageService,
    required FFmpegService ffmpegService,
    required GeminiService geminiService,
    required String scanId,
    required List<String> apiKeys,
    String mode = 'gemini',
  }) async {
    final scans = await storageService.loadScans();
    final scan = scans.where((s) => s.id == scanId).firstOrNull;
    if (scan == null || !MergePipelineService.pipelineReady(scan)) return null;

    if (mode == 'off') {
      return mode;
    }

    if (mode == 'twelvelabs') {
      if (MergePipelineService.isPipelineRunning(scanId)) return mode;
      final st = scan.pipelineStatus;
      if (st != null && st != 'idle') return mode;
      await MergePipelineService.startMergePipeline(
        storageService: storageService,
        scanId: scanId,
      );
      return mode;
    }

    // Default: 'gemini'
    if (apiKeys.isEmpty) {
      return mode;
    }

    if (GeminiMinuteFinderService.isMinuteFinderRunning(scanId)) {
      // Stop old and start fresh
      await GeminiMinuteFinderService.stopGeminiMinuteFinder(storageService, scanId);
    }

    await GeminiMinuteFinderService.startGeminiMinuteFinder(
      storageService: storageService,
      ffmpegService: ffmpegService,
      geminiService: geminiService,
      scanId: scanId,
      apiKeys: apiKeys,
      mode: 'start',
    );

    return mode;
  }
}
