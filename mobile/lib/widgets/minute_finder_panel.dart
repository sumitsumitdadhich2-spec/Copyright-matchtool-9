import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'minute_finder_toggle.dart';
import 'missing_scene_panel.dart';

/// 1:1 Port of components/cmt/minute-finder-panel.tsx
/// Auto Pipeline (Gemini Minute Finder vs TwelveLabs vs Off).

class MinuteFinderPanel extends StatefulWidget {
  final Scan scan;

  const MinuteFinderPanel({super.key, required this.scan});

  @override
  State<MinuteFinderPanel> createState() => _MinuteFinderPanelState();
}

class _MinuteFinderPanelState extends State<MinuteFinderPanel> {
  String _mode = 'gemini';
  String? _acting;
  String? _actionError;
  int? _openWindow;
  int? _openBackupWindow;

  static const List<Map<String, String>> _steps = [
    {'key': 'preparing', 'label': 'Prepare movie copy'},
    {'key': 'uploading', 'label': 'Upload'},
    {'key': 'scanning', 'label': 'Scan windows'},
    {'key': 'backup', 'label': 'Backup finder'},
    {'key': 'starting_scan', 'label': 'Minutes found'},
    {'key': 'done', 'label': 'Chunk scan started'},
  ];

  static const List<String> _activeStatuses = ['preparing', 'uploading', 'scanning', 'backup', 'starting_scan'];

  int _reachedStep(Map<String, dynamic>? prescan) {
    if (prescan == null) return 0;
    final status = prescan['status'] as String? ?? 'idle';
    if (status == 'done') return _steps.length;
    final idx = _steps.indexWhere((s) => s['key'] == status);
    if (idx >= 0) return idx;
    if ((prescan['minuteSuggestions'] as List?)?.isNotEmpty == true) return 4;
    if (prescan['backup'] != null && prescan['backup']['status'] != 'idle') return 3;
    if ((prescan['windows'] as List?)?.isNotEmpty == true) return 2;
    if ((prescan['uploads'] as Map?)?.isNotEmpty == true) return 1;
    return 0;
  }

  Future<void> _postAction(String action) async {
    setState(() {
      _acting = action;
      _actionError = null;
    });

    try {
      final res = await http.post(
        Uri.parse('/api/scans/${widget.scan.id}/minute-finder'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action}),
      );
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() => _actionError = j?['error'] as String? ?? 'Action failed');
      }
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  Future<void> _stop() async {
    setState(() {
      _acting = 'stop';
      _actionError = null;
    });

    try {
      final res = await http.delete(Uri.parse('/api/scans/${widget.scan.id}/minute-finder'));
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() => _actionError = j?['error'] as String? ?? 'Stop failed');
      }
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prescan = widget.scan.geminiPrescan;
    final status = prescan?['status'] as String? ?? widget.scan.prescanStatus;
    final isActive = _activeStatuses.contains(status);
    final isDone = status == 'done';
    final isError = status == 'error';
    final step = _reachedStep(prescan);

    final rawWindows = (prescan?['windows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final doneWindows = rawWindows.where((w) => w['status'] == 'done').length;
    final failedWindows = rawWindows.where((w) => w['status'] == 'failed').length;

    final backup = prescan?['backup'] as Map<String, dynamic>?;
    final backupWindows = (backup?['windows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final backupFailed = backupWindows.where((w) => w['status'] == 'failed').length;
    final backupAdded = (backup?['addedMinutes'] as List?)?.cast<int>() ?? [];

    final minutes = (prescan?['appliedMinutes'] as List?)?.cast<int>() ??
        (prescan?['minuteSuggestions'] as List?)?.map((s) => (s['minute'] as num).toInt()).toList() ??
        [];

    final totalFailed = failedWindows + backupFailed;
    final canStart = _mode == 'gemini' && !isActive && (status == 'idle' || isError) && !isDone;
    final canRetry = _mode == 'gemini' && !isActive && (totalFailed > 0 || (isError && rawWindows.isNotEmpty));
    final canRerun = _mode == 'gemini' && !isActive && rawWindows.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + MinuteFinderToggle
          Row(
            children: [
              const Icon(Icons.layers_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Auto Pipeline ${_mode == "gemini" ? "(Gemini Minute Finder)" : _mode == "twelvelabs" ? "(TwelveLabs)" : "(off)"}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              MinuteFinderToggle(
                mode: _mode,
                onChanged: (m) => setState(() => _mode = m),
              ),
            ],
          ),

          if (_mode == 'off') ...[
            const SizedBox(height: 8),
            const Text(
              'Minute finder OFF hai — upload + trim ke baad kuch auto nahi chalega. Manual Start scan dabane par normal FULL scan hoga.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],

          if (_mode == 'twelvelabs') ...[
            const SizedBox(height: 8),
            const Text(
              'TwelveLabs mode — purana merge → Marengo → Pegasus → minute approval flow chalta hai.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],

          if (_mode == 'gemini') ...[
            const SizedBox(height: 10),
            // Actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canStart)
                  ElevatedButton.icon(
                    onPressed: _acting != null ? null : () => _postAction('start'),
                    icon: _acting == 'start'
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black))
                        : const Icon(Icons.play_arrow, size: 14),
                    label: Text(_acting == 'start' ? 'Starting...' : 'Start minute finder', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                if (canRetry)
                  ElevatedButton.icon(
                    onPressed: _acting != null ? null : () => _postAction('retry'),
                    icon: _acting == 'retry'
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black))
                        : const Icon(Icons.refresh, size: 14),
                    label: Text('Retry failed windows${totalFailed > 0 ? " ($totalFailed)" : ""}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                if (canRerun)
                  OutlinedButton.icon(
                    onPressed: _acting != null ? null : () => _postAction('rerun'),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Re-run minute finder', style: TextStyle(fontSize: 11)),
                  ),
                if (isActive)
                  ElevatedButton.icon(
                    onPressed: _acting != null ? null : _stop,
                    icon: const Icon(Icons.stop, size: 14),
                    label: const Text('Stop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive),
                  ),
              ],
            ),

            if (_actionError != null) ...[
              const SizedBox(height: 6),
              Text(_actionError!, style: const TextStyle(fontSize: 11, color: AppTheme.destructive)),
            ],

            // Step Progress Timeline
            if (isActive || isDone || isError) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _steps.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final s = entry.value;
                    final done = step > idx || isDone;
                    final active = isActive && step == idx;
                    final failed = isError && step == idx;

                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: done
                                ? AppTheme.success.withOpacity(0.15)
                                : active
                                    ? AppTheme.primary.withOpacity(0.15)
                                    : failed
                                        ? AppTheme.destructive.withOpacity(0.15)
                                        : AppTheme.secondary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (done)
                                const Icon(Icons.check, size: 12, color: AppTheme.success)
                              else if (active)
                                const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                              else if (failed)
                                const Icon(Icons.warning_amber_rounded, size: 12, color: AppTheme.destructive),
                              if (done || active || failed) const SizedBox(width: 4),
                              Text(
                                s['label']!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                  color: done
                                      ? AppTheme.success
                                      : active
                                          ? AppTheme.primary
                                          : failed
                                              ? AppTheme.destructive
                                              : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (idx < _steps.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.arrow_forward, size: 10, color: AppTheme.textMuted),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],

            // Minutes Found Banner
            if (minutes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: AppTheme.success),
                        const SizedBox(width: 6),
                        Text(
                          'Movie minute ${minutes.join(", ")} found (${rawWindows.length} windows · ±1 min buffer)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: minutes.map((m) {
                        final fromBackup = backupAdded.contains(m);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: fromBackup ? AppTheme.primary.withOpacity(0.15) : AppTheme.card,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: fromBackup ? AppTheme.primary : AppTheme.success.withOpacity(0.3)),
                          ),
                          child: Text(
                            '$m: ${formatSeconds(m * 60)}–${formatSeconds((m + 1) * 60)}${fromBackup ? " [BK]" : ""}',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: fromBackup ? AppTheme.primary : AppTheme.success,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            // Windows Grid
            if (rawWindows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Windows (${doneWindows}/${rawWindows.length} done${failedWindows > 0 ? ", $failedWindows failed" : ""}) — short @10fps + window @1fps',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 6),
              ...rawWindows.map((w) {
                final idx = (w['index'] as num?)?.toInt() ?? 0;
                final wStatus = w['status'] as String? ?? 'pending';
                final matchesCount = (w['matches'] as num?)?.toInt() ?? 0;
                final isOpen = _openWindow == idx;

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: matchesCount > 0 ? AppTheme.success.withOpacity(0.4) : AppTheme.border,
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      'Window ${idx + 1}: ${formatSeconds((w["startSec"] as num?)?.toDouble() ?? (idx * 1200.0))} – ${formatSeconds((w["endSec"] as num?)?.toDouble() ?? ((idx + 1) * 1200.0))}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Status: $wStatus · Matches: $matchesCount', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    trailing: Icon(isOpen ? Icons.expand_less : Icons.expand_more, size: 16),
                    onTap: () => setState(() => _openWindow = isOpen ? null : idx),
                  ),
                );
              }),
            ],

            // Missing Scene Panel
            MissingScenePanel(scan: widget.scan),
          ],
        ],
      ),
    );
  }
}
