import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class CandidateChooserWidget extends StatefulWidget {
  final Scan scan;
  final ChunkMatch? selectedMatch;
  final ValueChanged<ChunkMatch>? onMatchChanged;

  const CandidateChooserWidget({
    super.key,
    required this.scan,
    this.selectedMatch,
    this.onMatchChanged,
  });

  @override
  State<CandidateChooserWidget> createState() => _CandidateChooserWidgetState();
}

class _CandidateChooserWidgetState extends State<CandidateChooserWidget> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.selectedMatch != null) {
      final idx = widget.scan.matches.indexOf(widget.selectedMatch!);
      if (idx >= 0) _currentIndex = idx;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    if (matches.isEmpty) return const SizedBox.shrink();

    final scanService = context.read<ScanService>();
    final safeIndex = _currentIndex.clamp(0, matches.length - 1);
    final match = matches[safeIndex];
    final isVerified = match.verified == true;

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
              Row(
                children: [
                  const Icon(Icons.tune, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Candidate Browser (${safeIndex + 1}/${matches.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isVerified ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isVerified ? 'MAIN: VERIFIED TRUE' : 'UNVERIFIED / CANDIDATE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isVerified ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Match details card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Short: ${Formatters.formatDuration(match.shortStart)} - ${Formatters.formatDuration(match.shortEnd)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Duration: ${match.duration.toStringAsFixed(1)}s',
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Movie Match: ${Formatters.formatDuration(match.movieStart)} - ${Formatters.formatDuration(match.movieEnd)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                    ),
                    Text(
                      'Score: ${(match.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (match.reason != null && match.reason!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'AI Forensic Note: ${match.reason!}',
                    style: const TextStyle(fontSize: 10, color: Colors.white70, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Stepper & Action buttons
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: safeIndex > 0
                    ? () {
                        setState(() => _currentIndex--);
                        widget.onMatchChanged?.call(matches[_currentIndex]);
                      }
                    : null,
                icon: const Icon(Icons.chevron_left, size: 16),
                label: const Text('Prev', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: safeIndex < matches.length - 1
                    ? () {
                        setState(() => _currentIndex++);
                        widget.onMatchChanged?.call(matches[_currentIndex]);
                      }
                    : null,
                icon: const Icon(Icons.chevron_right, size: 16),
                label: const Text('Next', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  scanService.verifyMatch(match);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Re-verifying Match #${safeIndex + 1} with 24fps AI Verifier...')),
                  );
                },
                icon: const Icon(Icons.verified, size: 14),
                label: const Text('Verify Clip', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
