import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';

class GapBackupPanel extends StatefulWidget {
  final Scan scan;

  const GapBackupPanel({super.key, required this.scan});

  @override
  State<GapBackupPanel> createState() => _GapBackupPanelState();
}

class _GapBackupPanelState extends State<GapBackupPanel> {
  bool _scanningGaps = false;

  @override
  Widget build(BuildContext context) {
    final shortDur = widget.scan.shortDuration ?? 60.0;
    final matches = widget.scan.matches;
    final scanService = context.read<ScanService>();

    // Calculate covered vs gap segments
    double matchedSecs = 0.0;
    for (final m in matches) {
      matchedSecs += (m.shortEnd - m.shortStart).clamp(0.0, shortDur);
    }
    final gapSecs = (shortDur - matchedSecs).clamp(0.0, shortDur);
    final coveragePct = ((matchedSecs / (shortDur > 0 ? shortDur : 1.0)) * 100.0).clamp(0.0, 100.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Gap Backup Scanner',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${coveragePct.toStringAsFixed(1)}% COVERED',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Detects unmapped intervals in the short video and performs a targeted second pass to discover fast transitions or missing cuts.',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.65)),
          ),
          const SizedBox(height: 12),

          // Visual Coverage Tape
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF27272A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: coveragePct.toInt(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.horizontal(
                        left: const Radius.circular(6),
                        right: Radius.circular(coveragePct >= 99 ? 6 : 0),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: (100 - coveragePct).toInt(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.4),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(coveragePct <= 1 ? 6 : 0),
                        right: const Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Matched: ${matchedSecs.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 10, color: Color(0xFF34D399)),
              ),
              Text(
                'Unmapped Gap: ${gapSecs.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 10, color: Color(0xFFF87171)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_scanningGaps || gapSecs < 1.0)
                  ? null
                  : () async {
                      setState(() => _scanningGaps = true);
                      await scanService.scanGaps();
                      if (mounted) setState(() => _scanningGaps = false);
                    },
              icon: _scanningGaps
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.radar, size: 16),
              label: Text(
                gapSecs < 1.0 ? '100% Coverage Reached' : 'Scan Missing Gaps (${gapSecs.toStringAsFixed(1)}s)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF59E0B),
                side: const BorderSide(color: Color(0xFFF59E0B)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
