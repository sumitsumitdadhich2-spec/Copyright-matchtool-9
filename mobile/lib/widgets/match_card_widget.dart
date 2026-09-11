import 'package:flutter/material.dart';
import '../models/chunk.dart';
import '../utils/formatters.dart';

class MatchCardWidget extends StatelessWidget {
  final ChunkMatch match;
  final int index;
  final VoidCallback? onPlayShort;
  final VoidCallback? onPlayMovie;
  final VoidCallback? onCompare;
  final VoidCallback? onVerify;
  final VoidCallback? onRescan;
  final bool isVerifying;
  final bool isRescanning;

  const MatchCardWidget({
    super.key,
    required this.match,
    required this.index,
    this.onPlayShort,
    this.onPlayMovie,
    this.onCompare,
    this.onVerify,
    this.onRescan,
    this.isVerifying = false,
    this.isRescanning = false,
  });

  @override
  Widget build(BuildContext context) {
    final sDuration = match.duration;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: match.verified == true
              ? const Color(0xFF22C55E).withOpacity(0.5)
              : match.verified == false
                  ? const Color(0xFFEF4444).withOpacity(0.4)
                  : const Color(0xFF2E2E2E),
          width: 1,
        ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (match.chunkIndex != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Chunk ${match.chunkIndex! + 1}',
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                ],
              ),
              _buildVerificationBadge(),
            ],
          ),
          const SizedBox(height: 12),
          // Short vs Movie Timestamps
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SHORT VIDEO',
                        style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Formatters.formatDuration(match.shortStart)} - ${Formatters.formatDuration(match.shortEnd)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF60A5FA),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 16, color: Colors.white30),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MOVIE TIMELINE',
                        style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${Formatters.formatDuration(match.movieStart)} - ${Formatters.formatDuration(match.movieEnd)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Duration: ${sDuration.toStringAsFixed(2)}s',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
              if (match.model != null) ...[
                const SizedBox(width: 10),
                Text(
                  '• ${match.model}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ],
          ),
          if (match.reason != null && match.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Verdict reason: ${match.reason}',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: match.verified == true ? const Color(0xFF22C55E) : Colors.redAccent,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Action Buttons
          Row(
            children: [
              if (onPlayShort != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPlayShort,
                    icon: const Icon(Icons.play_circle_outline, size: 14),
                    label: const Text('Play Short', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (onPlayMovie != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPlayMovie,
                    icon: const Icon(Icons.movie_outlined, size: 14),
                    label: const Text('Play Movie', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              if (onVerify != null && match.verified == null)
                IconButton(
                  onPressed: isVerifying ? null : onVerify,
                  tooltip: 'Verify with 3.5-shiva-lite (24fps)',
                  icon: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 20, color: Color(0xFFF59E0B)),
                ),
              if (onRescan != null)
                IconButton(
                  onPressed: isRescanning ? null : onRescan,
                  tooltip: 'Deep 24fps Rescan with 3-shiva-preview',
                  icon: isRescanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
                        )
                      : const Icon(Icons.radar_outlined, size: 20, color: Color(0xFF818CF8)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge() {
    if (match.rescanStatus == 'running') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF818CF8)),
            ),
            SizedBox(width: 5),
            Text(
              'RESCANNING...',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF818CF8)),
            ),
          ],
        ),
      );
    } else if (match.rescanStatus == 'found') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 12, color: Color(0xFF818CF8)),
            SizedBox(width: 4),
            Text(
              'RESCAN CONFIRMED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF818CF8)),
            ),
          ],
        ),
      );
    } else if (match.verified == true) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF22C55E).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 12, color: Color(0xFF22C55E)),
            SizedBox(width: 4),
            Text(
              'VERIFIED SAME',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
            ),
          ],
        ),
      );
    } else if (match.verified == false) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 12, color: Color(0xFFEF4444)),
            SizedBox(width: 4),
            Text(
              'DIFFERENT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'UNVERIFIED',
        style: TextStyle(fontSize: 10, color: Colors.white60),
      ),
    );
  }
}
