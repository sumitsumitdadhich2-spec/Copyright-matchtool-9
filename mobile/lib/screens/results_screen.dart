import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/match_card_widget.dart';

class ResultsScreen extends StatefulWidget {
  final Scan scan;
  final ChunkMatch? selectedMatch;

  const ResultsScreen({
    super.key,
    required this.scan,
    this.selectedMatch,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late int _currentIndex;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedMatch != null) {
      _currentIndex = widget.scan.matches.indexOf(widget.selectedMatch!);
      if (_currentIndex < 0) _currentIndex = 0;
    } else {
      _currentIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;

    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Match Results')),
        body: const Center(
          child: Text('No matches available to display.'),
        ),
      );
    }

    final currentMatch = matches[_currentIndex.clamp(0, matches.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Text('Match ${_currentIndex + 1} of ${matches.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share match timestamps',
            onPressed: () {
              final text = 'Forensic Match #${_currentIndex + 1}:\n'
                  'Short: ${Formatters.formatDuration(currentMatch.shortStart)} - ${Formatters.formatDuration(currentMatch.shortEnd)}\n'
                  'Movie: ${Formatters.formatDuration(currentMatch.movieStart)} - ${Formatters.formatDuration(currentMatch.movieEnd)}\n'
                  'Duration: ${currentMatch.duration.toStringAsFixed(2)}s';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Timestamps copied to clipboard:\n$text')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Navigation controls for matches
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                ),
                Text(
                  'Match #${_currentIndex + 1} / ${matches.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentIndex < matches.length - 1
                      ? () => setState(() => _currentIndex++)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Short Video Player Segment
          if (widget.scan.shortPath != null) ...[
            VideoPlayerWidget(
              key: ValueKey('short_${currentMatch.shortStart}_$_currentIndex'),
              videoPath: widget.scan.shortPath!,
              initialPosition: currentMatch.shortStart,
              targetEnd: currentMatch.shortEnd,
              title: 'Short Video Segment (${Formatters.formatDuration(currentMatch.shortStart)})',
            ),
            const SizedBox(height: 14),
          ],

          // Movie Video Player Segment
          if (widget.scan.moviePath != null) ...[
            VideoPlayerWidget(
              key: ValueKey('movie_${currentMatch.movieStart}_$_currentIndex'),
              videoPath: widget.scan.moviePath!,
              initialPosition: currentMatch.movieStart,
              targetEnd: currentMatch.movieEnd,
              title: 'Movie Window (${Formatters.formatDuration(currentMatch.movieStart)})',
            ),
            const SizedBox(height: 16),
          ],

          // Detailed Match Card
          MatchCardWidget(
            match: currentMatch,
            index: _currentIndex,
            isVerifying: _isVerifying,
            onVerify: () async {
              setState(() => _isVerifying = true);
              final scanService = context.read<ScanService>();
              final success = await scanService.verifyMatch(currentMatch);
              if (mounted) {
                setState(() => _isVerifying = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Verification confirmed: SAME recording!'
                          : 'Verifier verdict: DIFFERENT footage.',
                    ),
                    backgroundColor: success ? const Color(0xFF22C55E) : Colors.redAccent,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 16),

          // All matches quick picker
          const Text(
            'All Detected Matches',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...List.generate(matches.length, (i) {
            final m = matches[i];
            final isSelected = i == _currentIndex;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6366F1).withOpacity(0.15) : const Color(0xFF161616),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF6366F1) : Colors.white10,
                ),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  '#${i + 1} · Short: ${Formatters.formatTimeShort(m.shortStart)} -> Movie: ${Formatters.formatTimeShort(m.movieStart)}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF818CF8) : Colors.white70,
                  ),
                ),
                trailing: Text(
                  '${m.duration.toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                onTap: () {
                  setState(() => _currentIndex = i);
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
