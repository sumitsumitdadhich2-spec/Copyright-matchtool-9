import 'package:flutter/material.dart';
import '../models/scan.dart';

class LiveActivityBar extends StatelessWidget {
  final Scan scan;

  const LiveActivityBar({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final stages = [
      {'name': 'Upload', 'active': scan.shortPath != null && scan.moviePath != null},
      {'name': '24fps Chunk', 'active': scan.status == ScanStatus.chunking || scan.chunkCount > 0},
      {'name': 'AI Scan', 'active': scan.status == ScanStatus.scanning || scan.completedChunksCount > 0},
      {'name': 'Verifier', 'active': scan.verifiedMatchesCount > 0 || scan.status == ScanStatus.verifying},
      {'name': 'Report', 'active': scan.report != null || scan.status == ScanStatus.done},
    ];

    Color statusColor;
    String statusLabel;
    switch (scan.status) {
      case ScanStatus.chunking:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'CHUNKING ${scan.chunkingProgress.toInt()}%';
        break;
      case ScanStatus.scanning:
        statusColor = const Color(0xFF38BDF8);
        statusLabel = 'SCANNING ${scan.completedChunksCount}/${scan.chunkCount}';
        break;
      case ScanStatus.verifying:
        statusColor = const Color(0xFFA855F7);
        statusLabel = '24FPS VERIFYING';
        break;
      case ScanStatus.done:
        statusColor = const Color(0xFF10B981);
        statusLabel = 'SCAN COMPLETE';
        break;
      case ScanStatus.stopped:
        statusColor = const Color(0xFF94A3B8);
        statusLabel = 'PAUSED / STOPPED';
        break;
      case ScanStatus.error:
        statusColor = const Color(0xFFEF4444);
        statusLabel = 'ERROR';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusLabel = 'READY';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                '${(scan.overallProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: scan.overallProgress,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 10),
          // Micro stage chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: stages.map((s) {
              final active = s['active'] as bool;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? statusColor.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s['name'] as String,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? statusColor : Colors.white38,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
