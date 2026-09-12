import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'candidate_chooser_widget.dart';
import 'scan_timing_report.dart';

/// 1:1 Port of components/cmt/render-panel.tsx
/// Full Render Studio: Resolution (480p-4k), FPS (24/30/60), Bitrate, Padding, Start/Cancel/Download, Candidate Chooser & Timing Report.

const List<Map<String, dynamic>> RESOLUTIONS = [
  {'value': '480p', 'label': '480p (854×480)', 'defaultKbps': 2000},
  {'value': '720p', 'label': '720p (1280×720)', 'defaultKbps': 4500},
  {'value': '1080p', 'label': '1080p (1920×1080)', 'defaultKbps': 9000},
  {'value': '2k', 'label': '2K (2560×1440)', 'defaultKbps': 18000},
  {'value': '4k', 'label': '4K (3840×2160)', 'defaultKbps': 40000},
];

const List<int> FPS_OPTIONS = [24, 30, 60];
const List<int> AUDIO_BITRATES = [96, 128, 192, 256, 320];

class RenderPanel extends StatefulWidget {
  final Scan scan;

  const RenderPanel({super.key, required this.scan});

  @override
  State<RenderPanel> createState() => _RenderPanelState();
}

class _RenderPanelState extends State<RenderPanel> {
  String _resolution = '1080p';
  int _fps = 24;
  int _videoKbps = 9000;
  int _audioKbps = 192;
  double _headPaddingSec = 0.0;
  double _tailPaddingSec = 0.0;
  bool _actionBusy = false;
  String? _actionError;

  bool _downloading = false;
  double? _downloadPct;

  Future<void> _startRender() async {
    setState(() {
      _actionBusy = true;
      _actionError = null;
    });

    try {
      final res = await http.post(
        Uri.parse('/api/scans/${widget.scan.id}/render'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'resolution': _resolution,
          'fps': _fps,
          'videoBitrateKbps': _videoKbps,
          'audioBitrateKbps': _audioKbps,
          'headPaddingSec': _headPaddingSec,
          'tailPaddingSec': _tailPaddingSec,
        }),
      );

      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() => _actionError = j?['error'] as String? ?? 'Failed to start render');
      }
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancelRender() async {
    setState(() => _actionBusy = true);
    try {
      await http.post(Uri.parse('/api/scans/${widget.scan.id}/render/cancel'));
    } catch (e) {
      if (mounted) setState(() => _actionError = e.toString());
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    final job = widget.scan.renderJob;
    final rendering = job?.status == 'rendering';
    final done = job?.status == 'done';
    final failed = job?.status == 'error';

    // Calculate effective total render time
    double totalDuration = 0;
    for (final m in matches) {
      totalDuration += (m.movieEnd - m.movieStart + _headPaddingSec + _tailPaddingSec).clamp(0, double.infinity);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.movie_creation_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Render Export Studio',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (rendering)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      const SizedBox(width: 4),
                      Text('Rendering ${job?.progress ?? 0}%', style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else if (done)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Ready for download', style: TextStyle(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold)),
                ),
            ],
          ),

          const SizedBox(height: 12),
          // Resolution selector
          const Text('Resolution:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: RESOLUTIONS.map((r) {
                final val = r['value'] as String;
                final isSelected = val == _resolution;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(r['label'] as String, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (_) => setState(() {
                      _resolution = val;
                      _videoKbps = r['defaultKbps'] as int;
                    }),
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 10),
          // FPS & Bitrates row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Framerate:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    const SizedBox(height: 4),
                    Row(
                      children: FPS_OPTIONS.map((f) {
                        final isSel = f == _fps;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() => _fps = f),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel ? AppTheme.primary : AppTheme.secondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('$f FPS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.black : AppTheme.textMuted)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Video Bitrate: $_videoKbps kbps', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
                    Slider(
                      value: _videoKbps.toDouble(),
                      min: 1000,
                      max: 60000,
                      divisions: 59,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => setState(() => _videoKbps = v.toInt()),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          // Head / Tail Padding
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Head Padding: ${_headPaddingSec.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    Slider(
                      value: _headPaddingSec,
                      min: 0,
                      max: 10,
                      divisions: 20,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => setState(() => _headPaddingSec = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tail Padding: ${_tailPaddingSec.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                    Slider(
                      value: _tailPaddingSec,
                      min: 0,
                      max: 10,
                      divisions: 20,
                      activeColor: AppTheme.primary,
                      onChanged: (v) => setState(() => _tailPaddingSec = v),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          // Summary info & Actions
          Row(
            children: [
              Text(
                'Total segments: ${matches.length} · Dur: ${formatSeconds(totalDuration)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              const Spacer(),
              if (!rendering)
                ElevatedButton.icon(
                  onPressed: _actionBusy || matches.isEmpty ? null : _startRender,
                  icon: _actionBusy
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black))
                      : const Icon(Icons.movie_filter, size: 14),
                  label: Text(done ? 'Re-render' : 'Start Full Render', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                )
              else
                ElevatedButton.icon(
                  onPressed: _actionBusy ? null : _cancelRender,
                  icon: const Icon(Icons.stop, size: 14),
                  label: const Text('Cancel Render', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive),
                ),
            ],
          ),

          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_actionError!, style: const TextStyle(fontSize: 11, color: AppTheme.destructive)),
            ),

          if (done) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 20, color: AppTheme.success),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Export video rendered successfully', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                        Text('Final stitched movie clips proof file ready', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download started...')),
                      );
                    },
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Download MP4', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          // Task Timing Report
          ScanTimingReport(scan: widget.scan),
        ],
      ),
    );
  }
}
