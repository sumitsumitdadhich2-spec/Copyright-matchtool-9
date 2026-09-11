import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/formatters.dart';

class ShortCoverageWidget extends StatelessWidget {
  final Scan scan;

  const ShortCoverageWidget({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final shortDur = scan.shortDuration ?? (scan.matches.isNotEmpty ? scan.matches.last.shortEnd : 60.0);
    final coveragePct = scan.coveragePercent;
    final totalMatches = scan.matches.length;
    final verifiedMatches = scan.matches.where((m) => m.verified == true).length;
    final gaps = scan.unmappedGaps;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_outline, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Short Video Forensic Coverage',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${coveragePct.toStringAsFixed(1)}% MAPPED',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Short video total length: ${Formatters.formatDuration(shortDur)} • $verifiedMatches / $totalMatches verified matches',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),

          // Visual Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 12,
              color: const Color(0xFF27272A),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: (coveragePct / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF059669), Color(0xFF10B981)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Details Grid
          Row(
            children: [
              Expanded(
                child: _buildItem(
                  'Mapped Duration',
                  Formatters.formatDuration((coveragePct / 100) * shortDur),
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildItem(
                  'Unmapped Gaps',
                  '${gaps.length} gaps',
                  gaps.isEmpty ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildItem(
                  '24fps Verified',
                  '$verifiedMatches clips',
                  const Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
