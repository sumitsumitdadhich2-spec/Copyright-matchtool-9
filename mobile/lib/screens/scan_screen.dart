import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../services/settings_service.dart';
import '../widgets/scan_progress_widget.dart';
import '../widgets/chunk_timeline_widget.dart';
import '../widgets/match_card_widget.dart';
import 'results_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  int? _verifyingIndex;
  int? _rescanningIndex;

  @override
  Widget build(BuildContext context) {
    final scanService = context.watch<ScanService>();
    final settings = context.watch<SettingsService>();
    final scan = scanService.currentScan;

    if (scan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Forensic Scanner')),
        body: const Center(
          child: Text('No active scan found.'),
        ),
      );
    }

    final isScanning = scanService.isScanning;
    final matches = scan.matches;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          scan.shortName ?? 'Active Scan',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (matches.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ResultsScreen(scan: scan)),
                );
              },
              icon: const Icon(Icons.compare_arrows, size: 18, color: Color(0xFF22C55E)),
              label: Text(
                'Results (${matches.length})',
                style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress & Control Card
          ScanProgressWidget(
            scan: scan,
            onStop: isScanning
                ? () {
                    scanService.stopScan();
                  }
                : null,
            onResume: (!isScanning && scan.status == ScanStatus.stopped)
                ? () {
                    scanService.configureGemini(settings.apiKey!, model: settings.selectedModel);
                    scanService.startScan(autoVerify: settings.autoVerify);
                  }
                : null,
          ),
          const SizedBox(height: 16),

          // Chunk Status Timeline Grid
          ChunkTimelineWidget(
            chunks: scan.chunks,
            onRetryChunk: (index) {
              scanService.retryChunk(index);
            },
          ),
          const SizedBox(height: 20),

          // Discovered Matches Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detected Matches (${matches.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (matches.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ResultsScreen(scan: scan)),
                    );
                  },
                  child: const Text('Open Comparison Player', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (matches.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isScanning ? Icons.search : Icons.info_outline,
                      size: 32,
                      color: Colors.white30,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isScanning
                          ? 'Scanning 24fps frames with Gemini...\nMatches will appear here.'
                          : 'No matches detected in scanned chunks.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(matches.length, (i) {
              final match = matches[i];
              return MatchCardWidget(
                match: match,
                index: i,
                isVerifying: _verifyingIndex == i,
                isRescanning: _rescanningIndex == i,
                onPlayShort: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultsScreen(
                        scan: scan,
                        selectedMatch: match,
                      ),
                    ),
                  );
                },
                onPlayMovie: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultsScreen(
                        scan: scan,
                        selectedMatch: match,
                      ),
                    ),
                  );
                },
                onVerify: () async {
                  setState(() => _verifyingIndex = i);
                  final success = await scanService.verifyMatch(match);
                  if (mounted) {
                    setState(() => _verifyingIndex = null);
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
                onRescan: () async {
                  setState(() => _rescanningIndex = i);
                  await scanService.rescanCandidate(match);
                  if (mounted) {
                    setState(() => _rescanningIndex = null);
                    final isFound = match.rescanStatus == 'found';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isFound
                              ? 'Rescan confirmed true match in chunk!'
                              : 'Rescan: Target segment not found in this chunk.',
                        ),
                        backgroundColor: isFound ? const Color(0xFF6366F1) : Colors.amber.shade800,
                      ),
                    );
                  }
                },
              );
            }),
        ],
      ),
    );
  }
}
