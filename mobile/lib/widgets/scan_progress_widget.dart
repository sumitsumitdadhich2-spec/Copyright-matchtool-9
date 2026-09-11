import 'package:flutter/material.dart';
import '../models/chunk.dart';
import '../models/scan.dart';

class ScanProgressWidget extends StatelessWidget {
  final Scan scan;
  final VoidCallback? onStop;
  final VoidCallback? onResume;

  const ScanProgressWidget({
    super.key,
    required this.scan,
    this.onStop,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final isChunking = scan.status == ScanStatus.chunking;
    final isScanning = scan.status == ScanStatus.scanning;
    final isStopped = scan.status == ScanStatus.stopped;
    final isDone = scan.status == ScanStatus.done;
    final isError = scan.status == ScanStatus.error;

    final processedChunks = scan.chunks
        .where((c) =>
            c.status == ChunkStatus.match ||
            c.status == ChunkStatus.noMatch ||
            c.status == ChunkStatus.failed)
        .length;

    final progress = isChunking
        ? (scan.chunkingProgress / 100.0)
        : (scan.chunkCount > 0 ? (processedChunks / scan.chunkCount) : 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildStatusIcon(scan.status),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusTitle(scan.status),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      _getStatusSubtitle(scan, processedChunks),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isScanning && onStop != null)
                TextButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 18),
                  label: const Text('Stop', style: TextStyle(color: Colors.redAccent)),
                ),
              if (isStopped && onResume != null)
                TextButton.icon(
                  onPressed: onResume,
                  icon: const Icon(Icons.play_circle_outlined, color: Color(0xFF22C55E), size: 18),
                  label: const Text('Resume', style: TextStyle(color: Color(0xFF22C55E))),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone
                    ? const Color(0xFF22C55E)
                    : isError
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6366F1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(0)}% completed',
                style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                    ),
                    child: Text(
                      '${scan.matches.length} matches',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '≤ 5 CPU Cores',
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ScanStatus status) {
    switch (status) {
      case ScanStatus.chunking:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFF59E0B)),
        );
      case ScanStatus.scanning:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF6366F1)),
        );
      case ScanStatus.done:
        return const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 24);
      case ScanStatus.error:
        return const Icon(Icons.error, color: Color(0xFFEF4444), size: 24);
      case ScanStatus.stopped:
        return const Icon(Icons.pause_circle_filled, color: Colors.orangeAccent, size: 24);
      default:
        return const Icon(Icons.pending, color: Colors.grey, size: 24);
    }
  }

  String _getStatusTitle(ScanStatus status) {
    switch (status) {
      case ScanStatus.chunking:
        return 'Chunking Movie Video...';
      case ScanStatus.scanning:
        return 'Analyzing Video Chunks with Gemini';
      case ScanStatus.done:
        return 'Forensic Scan Complete';
      case ScanStatus.error:
        return 'Scan Interrupted by Error';
      case ScanStatus.stopped:
        return 'Scan Paused';
      default:
        return 'Ready to Scan';
    }
  }

  String _getStatusSubtitle(Scan scan, int processed) {
    if (scan.status == ScanStatus.chunking) {
      return 'Generating 60s clips at 24fps (${scan.chunkingProgress.toStringAsFixed(0)}%)';
    }
    if (scan.chunkCount > 0) {
      return 'Processed $processed of ${scan.chunkCount} chunks';
    }
    return 'Waiting to begin analysis';
  }
}
