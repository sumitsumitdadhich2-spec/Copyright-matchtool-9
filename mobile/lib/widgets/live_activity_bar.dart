import 'dart:async';
import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/live-activity-bar.tsx
/// Top-level live system activity bar showing real-time scanning/rendering/batch verifying/rescan state with progress bar & ticker.

class LiveActivityBar extends StatefulWidget {
  final Scan scan;
  final VoidCallback? onScrollToLogs;

  const LiveActivityBar({
    super.key,
    required this.scan,
    this.onScrollToLogs,
  });

  @override
  State<LiveActivityBar> createState() => _LiveActivityBarState();
}

class _LiveActivityBarState extends State<LiveActivityBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;

    // 1. Batch Verifier active check
    final batchResults = scan.batchVerify?.results ?? {};
    final minuteEntries = batchResults.entries.toList();
    final verifyingMinute = minuteEntries.where((e) => e.value.status == 'verifying').firstOrNull;
    final completedMinutes = minuteEntries.where((e) => e.value.status == 'done').length;
    final totalMinutes = scan.shortDuration > 0 ? (scan.shortDuration / 60.0).ceil() : minuteEntries.length;

    // 2. Render / Export active check
    final isRendering = scan.renderJob?.status == 'rendering';
    final renderPct = scan.renderJob?.pct ?? 0;
    final renderEta = scan.renderJob?.etaSeconds;
    final renderSegments = scan.renderJob?.segmentCount ?? 0;

    // 3. Rescan active check
    final logs = scan.logs;
    final recentLogs = logs.length > 5 ? logs.sublist(logs.length - 5) : logs;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final activeRescanLog = recentLogs.where((l) {
      final msg = l.message;
      return msg.contains('[Rescan Scene]') &&
          !msg.contains('SUCCESS:') &&
          !msg.contains('Failed:') &&
          !msg.contains('did not find') &&
          (nowMs - l.timestamp) < 35000;
    }).firstOrNull;

    // 4. Scanning / Chunking active check
    final isChunking = scan.status == ScanStatus.chunking;
    final isScanning = scan.status == ScanStatus.scanning || scan.status == ScanStatus.verifying;

    // Priority Activity Calculation
    String badge;
    Color badgeBg;
    Color badgeBorder;
    Color badgeText;
    String title;
    String description;
    int progress;
    String progressLabel;
    IconData icon;
    bool isLive;

    if (isRendering) {
      badge = '🎬 Export Video Render';
      badgeBg = const Color(0xFFF59E0B).withOpacity(0.15);
      badgeBorder = const Color(0xFFF59E0B).withOpacity(0.4);
      badgeText = const Color(0xFFF59E0B);
      title = 'Abhi ye chal raha hai: Export Video Stitching';
      description = 'FFmpeg high-speed render: $renderSegments matched scenes ko sequence me merge kiya ja raha hai (Padding & Audio sync active).';
      progress = renderPct;
      progressLabel = '$renderPct% Complete${renderEta != null && renderEta > 0 ? " · ETA: ${renderEta}s" : ""}';
      icon = Icons.movie_filter_outlined;
      isLive = true;
    } else if (verifyingMinute != null) {
      final minNum = (int.tryParse(verifyingMinute.key) ?? 0) + 1;
      final partCount = verifyingMinute.value.parts.length;
      final activeModel = verifyingMinute.value.model ?? 'Gemini 3.6/3.7/3.8 Flash';
      badge = '🤖 24 FPS Batch Verifier';
      badgeBg = const Color(0xFF8B5CF6).withOpacity(0.15);
      badgeBorder = const Color(0xFF8B5CF6).withOpacity(0.4);
      badgeText = const Color(0xFF8B5CF6);
      title = 'Abhi ye chal raha hai: Minute $minNum (Batch Verify)';
      description = 'Minute $minNum ke $partCount matched scenes ko 24 FPS stitched video bana kar $activeModel se verify kiya ja raha hai.';
      progress = totalMinutes > 0 ? ((completedMinutes / totalMinutes) * 100).round() : 50;
      progressLabel = 'Min $minNum of $totalMinutes ($completedMinutes verified)';
      icon = Icons.smart_toy_outlined;
      isLive = true;
    } else if (activeRescanLog != null) {
      badge = '🎯 Targeted Scene Rescan';
      badgeBg = const Color(0xFF06B6D4).withOpacity(0.15);
      badgeBorder = const Color(0xFF06B6D4).withOpacity(0.4);
      badgeText = const Color(0xFF06B6D4);
      title = 'Abhi ye chal raha hai: Targeted Scene Rescan';
      description = activeRescanLog.message.replaceAll(RegExp('flash', caseSensitive: false), 'shiva');
      progress = 50;
      progressLabel = 'AI Rescan in progress...';
      icon = Icons.bolt;
      isLive = true;
    } else if (isChunking) {
      final pct = scan.chunkingProgress ?? 0;
      badge = '✂️ Video Splitting';
      badgeBg = const Color(0xFF3B82F6).withOpacity(0.15);
      badgeBorder = const Color(0xFF3B82F6).withOpacity(0.4);
      badgeText = const Color(0xFF3B82F6);
      title = 'Abhi ye chal raha hai: Movie 1-Minute Chunking';
      description = 'Movie ko 1-1 minute ke chunks me lossless split kiya ja raha hai taaki parallel AI scanning shuru ho sake.';
      progress = pct;
      progressLabel = '$pct% Split complete';
      icon = Icons.content_cut_outlined;
      isLive = true;
    } else if (isScanning) {
      final segCount = scan.shortSegments?.length ?? 0;
      final matchesCount = scan.matches.length;
      badge = '🔍 AI Multi-Engine Scanner';
      badgeBg = const Color(0xFF10B981).withOpacity(0.15);
      badgeBorder = const Color(0xFF10B981).withOpacity(0.4);
      badgeText = const Color(0xFF10B981);
      title = 'Abhi ye chal raha hai: Gemini Parallel 1-Prompt/Min Scan';
      description = 'Movie chunks ko Gemini parallel lanes par scan kiya ja raha hai ($matchesCount scenes already matched).';
      progress = segCount > 0 ? (matchesCount / (segCount * 5.0) * 100).round().clamp(5, 95) : 30;
      progressLabel = 'Scanning active · $matchesCount scenes found';
      icon = Icons.search;
      isLive = true;
    } else if (scan.status == ScanStatus.done || scan.status == ScanStatus.stopped) {
      final matches = scan.matches.length;
      final confirmed = scan.matches.where((m) => m.batchVerified == 'confirmed').length;
      final hasBatch = batchResults.isNotEmpty;
      badge = '✨ System Ready';
      badgeBg = const Color(0xFF10B981).withOpacity(0.1);
      badgeBorder = const Color(0xFF10B981).withOpacity(0.3);
      badgeText = const Color(0xFF10B981);
      title = 'System Ready: Scan Complete & Matched';
      description = hasBatch
          ? '$matches matched scenes available ($confirmed confirmed by 24fps Batch Verifier). Ready for export.'
          : '$matches matched scenes available. Batch Verifier chala kar 100% accuracy verify kar sakte hain ya export render kar sakte hain.';
      progress = 100;
      progressLabel = '$matches Scenes Ready';
      icon = Icons.check_circle_outline;
      isLive = false;
    } else {
      badge = '⚡ Ready';
      badgeBg = AppTheme.secondary;
      badgeBorder = AppTheme.border;
      badgeText = AppTheme.textMuted;
      title = 'Ready for Next Step';
      description = 'Short aur Movie ready hain. Scan shuru karne par yahan live progress dikhegi.';
      progress = 0;
      progressLabel = 'Idle';
      icon = Icons.auto_awesome;
      isLive = false;
    }

    final latestLog = logs.isNotEmpty ? logs.last : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive ? AppTheme.primary.withOpacity(0.5) : AppTheme.border,
          width: isLive ? 1.5 : 1,
        ),
        boxShadow: isLive
            ? [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isLive ? AppTheme.primary.withOpacity(0.15) : AppTheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isLive ? AppTheme.primary.withOpacity(0.4) : AppTheme.border),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isLive ? AppTheme.primary : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: badgeBorder),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Text(
                              scan.customName ?? scan.shortName ?? scan.movieName ?? 'Scan ${scan.id.substring(0, scan.id.length >= 6 ? 6 : scan.id.length)}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
                            ),
                          ),
                          if (isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.sensors, size: 10, color: AppTheme.primary),
                                  SizedBox(width: 3),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                // Jump to Logs
                OutlinedButton.icon(
                  onPressed: widget.onScrollToLogs,
                  icon: const Icon(Icons.layers_outlined, size: 12, color: AppTheme.primary),
                  label: Text('Logs (${logs.length})', style: const TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),

            // Progress Bar
            if (isLive && progress > 0) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.circle, size: 6, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text('Live Progress', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textForeground)),
                    ],
                  ),
                  Text(progressLabel, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (progress / 100.0).clamp(0.05, 1.0),
                  backgroundColor: AppTheme.secondary,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  minHeight: 4,
                ),
              ),
            ],

            // Latest Log Ticker
            if (latestLog != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      DateTime.fromMillisecondsSinceEpoch(latestLog.timestamp).toIso8601String().substring(11, 19),
                      style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppTheme.textMuted),
                    ),
                    const SizedBox(width: 6),
                    const Text('⚡ [Live]: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    Expanded(
                      child: Text(
                        latestLog.message.replaceAll(RegExp('flash', caseSensitive: false), 'shiva'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppTheme.textForeground),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
