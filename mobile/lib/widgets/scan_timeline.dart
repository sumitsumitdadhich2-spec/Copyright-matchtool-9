import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 1:1 Port of components/cmt/scan-timeline.tsx
/// Minute-by-minute scanning timeline with short minute tabs and color-coded status squares.

class ScanTimeline extends StatefulWidget {
  final Scan scan;

  const ScanTimeline({super.key, required this.scan});

  @override
  State<ScanTimeline> createState() => _ScanTimelineState();
}

class _ScanTimelineState extends State<ScanTimeline> {
  int? _selectedSegIdx;

  Color _getStatusColor(String status) {
    switch (status) {
      case 'scanning':
        return AppTheme.primary;
      case 'match':
        return AppTheme.destructive;
      case 'no_match':
        return AppTheme.success.withOpacity(0.7);
      case 'failed':
      case 'policy_blocked':
        return AppTheme.warning;
      case 'cancelled':
        return AppTheme.textMuted.withOpacity(0.5);
      case 'pending':
      default:
        return AppTheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final segs = widget.scan.shortSegments;
    final multi = segs.length > 1;
    final activeSeg = widget.scan.currentShortSegment ?? 0;
    final segIdx = _selectedSegIdx ?? activeSeg;

    if (widget.scan.chunkCount == 0) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scan Timeline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Upload a movie to see the minute-by-minute timeline.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    final chunks = widget.scan.chunks;
    final doneCount = chunks.where((c) => c.status == 'match' || c.status == 'no_match').length;

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
          // Header
          Row(
            children: [
              const Text('Scan Timeline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              if (multi) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'short minute ${segIdx + 1}/${segs.length}',
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.primary),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '$doneCount/${widget.scan.chunkCount} chunks',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
              ),
            ],
          ),

          // Short Segment Tabs
          if (multi) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: segs.map((seg) {
                  final isSel = seg.index == segIdx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _selectedSegIdx = seg.index == activeSeg ? null : seg.index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSel ? AppTheme.primary.withOpacity(0.15) : AppTheme.secondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSel ? AppTheme.primary : Colors.transparent),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Min ${seg.index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: isSel ? AppTheme.primary : AppTheme.textMuted,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (seg.status == 'done') ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check, size: 10, color: AppTheme.success),
                            ] else if (seg.status == 'scanning' || seg.status == 'verifying') ...[
                              const SizedBox(width: 4),
                              const SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 1.5)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 12),
          // Minute block grid
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: chunks.map((c) {
              final color = _getStatusColor(c.status);
              final timeStr = '${formatSeconds(c.index * 60)}–${formatSeconds((c.index + 1) * 60)}';

              return Tooltip(
                message: 'Minute ${c.index} ($timeStr) — ${c.status}${c.model != null ? " · ${c.model}" : ""}',
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          // Legend
          const Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _LegendDot(color: AppTheme.secondary, label: 'pending'),
              _LegendDot(color: AppTheme.primary, label: 'scanning'),
              _LegendDot(color: Color(0xFF10B981), label: 'no match'),
              _LegendDot(color: AppTheme.destructive, label: 'match'),
              _LegendDot(color: AppTheme.warning, label: 'failed'),
              _LegendDot(color: Colors.white24, label: 'cancelled'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
      ],
    );
  }
}
