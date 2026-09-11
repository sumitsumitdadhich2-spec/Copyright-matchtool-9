import 'package:flutter/material.dart';
import '../models/scan.dart';

class TopMilestoneBanner extends StatelessWidget {
  final Scan scan;
  final VoidCallback? onJumpToMatch;

  const TopMilestoneBanner({
    super.key,
    required this.scan,
    this.onJumpToMatch,
  });

  @override
  Widget build(BuildContext context) {
    final matchesCount = scan.matches.length;
    final verifiedCount = scan.verifiedMatchesCount;
    final rep = scan.report;

    if (matchesCount == 0 && scan.status != ScanStatus.scanning && scan.status != ScanStatus.chunking) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E293B),
            matchesCount > 0 ? const Color(0xFF0F172A) : const Color(0xFF18181B),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: matchesCount > 0 ? const Color(0xFF38BDF8).withOpacity(0.5) : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (matchesCount > 0 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B)).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              matchesCount > 0 ? Icons.verified_user : Icons.radar,
              color: matchesCount > 0 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      matchesCount > 0
                          ? '$matchesCount Match${matchesCount == 1 ? "" : "es"} Detected'
                          : 'Analyzing 24fps Frames...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (verifiedCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$verifiedCount AI-Verified',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rep != null
                      ? '${rep.matchPercentage.toStringAsFixed(1)}% match coverage (${rep.totalMatchedSeconds.toStringAsFixed(1)}s)'
                      : 'Movie: ${scan.movieName ?? "video"}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (matchesCount > 0 && onJumpToMatch != null)
            TextButton.icon(
              onPressed: onJumpToMatch,
              icon: const Icon(Icons.compare_arrows, size: 16, color: Color(0xFF38BDF8)),
              label: const Text('Compare', style: TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            ),
        ],
      ),
    );
  }
}
