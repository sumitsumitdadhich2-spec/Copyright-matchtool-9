import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import 'engine_badge_widget.dart';

/// 1:1 Port of components/cmt/logs-panel.tsx
/// Filterable live logging console with category pills, auto-scroll, search, copy & highlighted tags.

enum LogCategory {
  all,
  batch,
  render,
  rescan,
  scan,
  alerts,
}

class LogsPanel extends StatefulWidget {
  final Scan scan;

  const LogsPanel({super.key, required this.scan});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  LogCategory _category = LogCategory.all;
  String _search = '';
  bool _autoScroll = true;
  bool _copied = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant LogsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.scan.logs.length != oldWidget.scan.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 30;
    if (_autoScroll != isAtBottom) {
      setState(() {
        _autoScroll = isAtBottom;
      });
    }
  }

  bool _matcher(LogCategory cat, ScanLog l) {
    final msg = l.message.toLowerCase();
    switch (cat) {
      case LogCategory.all:
        return true;
      case LogCategory.batch:
        return msg.contains('batch') || msg.contains('stitch') || msg.contains('verdict') || msg.contains('confirmed via rescan');
      case LogCategory.render:
        return msg.contains('render') || msg.contains('export') || msg.contains('padding') || msg.contains('ffmpeg');
      case LogCategory.rescan:
        return msg.contains('rescan') || msg.contains('targeted') || msg.contains('re-tested');
      case LogCategory.scan:
        return msg.contains('chunk') || msg.contains('mapping short') || msg.contains('segment') || msg.contains('split');
      case LogCategory.alerts:
        return l.level == 'warn' || l.level == 'error' || msg.contains('quota') || msg.contains('exhausted') || msg.contains('rate limit');
    }
  }

  (String label, Color bg, Color border, Color text) _getCategoryTag(String msg, String level) {
    final m = msg.toLowerCase();
    if (m.contains('[batch verifier]') || m.contains('batch verify') || m.contains('stitched')) {
      return ('BATCH 24FPS', const Color(0xFF8B5CF6).withOpacity(0.12), const Color(0xFF8B5CF6).withOpacity(0.4), const Color(0xFF8B5CF6));
    }
    if (m.contains('render') || m.contains('export') || m.contains('padding') || m.contains('ffmpeg')) {
      return ('RENDER', const Color(0xFFF59E0B).withOpacity(0.12), const Color(0xFFF59E0B).withOpacity(0.4), const Color(0xFFF59E0B));
    }
    if (m.contains('[rescan') || m.contains('rescan:')) {
      return ('RESCAN', const Color(0xFF06B6D4).withOpacity(0.12), const Color(0xFF06B6D4).withOpacity(0.4), const Color(0xFF06B6D4));
    }
    if (m.contains('chunk ') || m.contains('chunking') || m.contains('mapping short')) {
      return ('SCAN', const Color(0xFF10B981).withOpacity(0.12), const Color(0xFF10B981).withOpacity(0.4), const Color(0xFF10B981));
    }
    if (level == 'error') {
      return ('ERROR', AppTheme.destructive.withOpacity(0.15), AppTheme.destructive.withOpacity(0.4), AppTheme.destructive);
    }
    if (level == 'warn') {
      return ('ALERT', const Color(0xFFF59E0B).withOpacity(0.15), const Color(0xFFF59E0B).withOpacity(0.4), const Color(0xFFF59E0B));
    }
    return ('SYSTEM', AppTheme.secondary, AppTheme.border, AppTheme.textMuted);
  }

  Future<void> _handleCopyLogs(List<ScanLog> logs) async {
    final text = logs.map((l) {
      final timeStr = DateTime.fromMillisecondsSinceEpoch(l.timestamp).toIso8601String().substring(11, 19);
      return '[$timeStr] [${l.level.toUpperCase()}] ${l.message}';
    }).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.scan.logs;
    final q = _search.trim().toLowerCase();

    final filteredLogs = logs.where((l) {
      if (!_matcher(_category, l)) return false;
      if (q.isNotEmpty && !l.message.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    // Category Counts
    final counts = <LogCategory, int>{};
    for (final cat in LogCategory.values) {
      counts[cat] = cat == LogCategory.all ? logs.length : logs.where((l) => _matcher(cat, l)).length;
    }

    // Live status
    final isRendering = widget.scan.renderJob?.status == 'rendering';
    final batchResults = widget.scan.batchVerify?.results ?? {};
    final verifying = batchResults.entries.where((e) => e.value.status == 'verifying').firstOrNull;
    final isChunking = widget.scan.status == ScanStatus.chunking;
    final isScanning = widget.scan.status == ScanStatus.scanning || widget.scan.status == ScanStatus.verifying;

    String liveText = 'System Ready · Total ${logs.length} logged events';
    Color liveColor = AppTheme.textMuted;
    bool liveActive = false;

    if (isRendering) {
      liveActive = true;
      liveText = 'Export Render Active: ${widget.scan.renderJob?.pct ?? 0}% · Movie scene stitching in progress';
      liveColor = const Color(0xFFF59E0B);
    } else if (verifying != null) {
      liveActive = true;
      final minNum = (int.tryParse(verifying.key) ?? 0) + 1;
      liveText = 'Batch 24fps Verifier Active: Minute $minNum verifying on Gemini';
      liveColor = const Color(0xFF8B5CF6);
    } else if (isChunking) {
      liveActive = true;
      liveText = 'Splitting Movie: ${widget.scan.chunkingProgress ?? 0}% chunks ready';
      liveColor = const Color(0xFF3B82F6);
    } else if (isScanning) {
      liveActive = true;
      liveText = 'AI Scanning in progress (${widget.scan.matches.length} matches found)';
      liveColor = const Color(0xFF10B981);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
                  ),
                  child: const Icon(Icons.terminal, size: 16, color: AppTheme.primary),
                ),
                const SizedBox(width: 8),
                const Text('Live Activity & Logs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    filteredLogs.length != logs.length ? '${filteredLogs.length} / ${logs.length}' : '${logs.length}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                  ),
                ),
                const Spacer(),
                const EngineBadgeWidget(live: true),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.pause, size: 16),
                  color: _autoScroll ? AppTheme.primary : AppTheme.textMuted,
                  tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll PAUSED',
                  onPressed: () => setState(() => _autoScroll = !_autoScroll),
                ),
                IconButton(
                  icon: Icon(_copied ? Icons.check : Icons.copy, size: 16, color: _copied ? AppTheme.success : AppTheme.textMuted),
                  tooltip: 'Copy Logs',
                  onPressed: filteredLogs.isEmpty ? null : () => _handleCopyLogs(filteredLogs),
                ),
              ],
            ),
            const Divider(height: 16),

            // Live Ribbon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 8, color: liveActive ? AppTheme.primary : AppTheme.textMuted),
                  const SizedBox(width: 8),
                  const Text('ABHI STATUS: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textForeground)),
                  Expanded(
                    child: Text(
                      liveText,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: liveColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Category Tabs & Search
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip(LogCategory.all, 'All Logs', counts[LogCategory.all] ?? 0, Icons.layers_outlined),
                        const SizedBox(width: 4),
                        _buildCategoryChip(LogCategory.batch, 'Batch 24fps', counts[LogCategory.batch] ?? 0, Icons.smart_toy_outlined),
                        const SizedBox(width: 4),
                        _buildCategoryChip(LogCategory.render, 'Render', counts[LogCategory.render] ?? 0, Icons.movie_filter_outlined),
                        const SizedBox(width: 4),
                        _buildCategoryChip(LogCategory.rescan, 'Rescan', counts[LogCategory.rescan] ?? 0, Icons.bolt),
                        const SizedBox(width: 4),
                        _buildCategoryChip(LogCategory.scan, 'Scanner', counts[LogCategory.scan] ?? 0, Icons.search),
                        const SizedBox(width: 4),
                        _buildCategoryChip(LogCategory.alerts, 'Alerts', counts[LogCategory.alerts] ?? 0, Icons.warning_amber_outlined),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Search Box
            TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _search = val),
              decoration: InputDecoration(
                hintText: 'Search logs...',
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),

            // Logs Box
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Text(
                        _search.isNotEmpty ? 'Koi log match nahi hua' : 'Is category me abhi tak koi log nahi hai',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, idx) {
                        final log = filteredLogs[idx];
                        final tag = _getCategoryTag(log.message, log.level);
                        final timeStr = DateTime.fromMillisecondsSinceEpoch(log.timestamp).toIso8601String().substring(11, 19);
                        final cleanMsg = log.message.replaceAll(RegExp('flash', caseSensitive: false), 'shiva');

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timeStr,
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: tag.$2,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: tag.$3),
                                ),
                                child: Text(
                                  tag.$1,
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: tag.$4),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildLogMessage(cleanMsg, log.level),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(LogCategory cat, String label, int count, IconData icon) {
    final active = _category == cat;
    return InkWell(
      onTap: () => setState(() => _category = cat),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(0.15) : AppTheme.secondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? AppTheme.primary : AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? AppTheme.primary : AppTheme.textMuted),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: active ? AppTheme.primary : AppTheme.textMuted.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogMessage(String msg, String level) {
    if (msg.contains('CONFIRMED')) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: msg.split('CONFIRMED')[0]),
            const WidgetSpan(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x3310B981), borderRadius: BorderRadius.all(Radius.circular(3))),
                  child: Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1), child: Text('CONFIRMED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981)))),
                ),
              ),
            ),
            TextSpan(text: msg.split('CONFIRMED').sublist(1).join('CONFIRMED')),
          ],
        ),
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textForeground),
      );
    }
    if (msg.contains('REJECTED')) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: msg.split('REJECTED')[0]),
            const WidgetSpan(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x33F43F5E), borderRadius: BorderRadius.all(Radius.circular(3))),
                  child: Padding(padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1), child: Text('REJECTED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFF43F5E)))),
                ),
              ),
            ),
            TextSpan(text: msg.split('REJECTED').sublist(1).join('REJECTED')),
          ],
        ),
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textForeground),
      );
    }
    Color color = AppTheme.textForeground;
    if (msg.contains('SUCCESS')) {
      color = AppTheme.success;
    } else if (level == 'error') {
      color = AppTheme.destructive;
    } else if (level == 'warn') {
      color = AppTheme.warning;
    }
    return Text(msg, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color));
  }
}
