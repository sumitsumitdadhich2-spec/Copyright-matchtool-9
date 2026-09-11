import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/scan_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import 'upload_screen.dart';
import 'scan_screen.dart';
import 'results_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final storage = context.watch<StorageService>();
    final scanService = context.watch<ScanService>();

    final hasApiKey = settings.hasApiKey;
    final activeScan = scanService.currentScan;
    final recentScans = storage.savedScans.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.radar, color: Color(0xFFF59E0B), size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  AppConstants.appSubtitle,
                  style: TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_outlined),
            tooltip: 'Past Scans',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: hasApiKey ? Colors.white : Colors.amberAccent,
            ),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // API Key Warning Banner if missing
          if (!hasApiKey)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gemini API Key Required',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Configure your personal API key to enable AI video matching.',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    child: const Text('Setup', style: TextStyle(color: Color(0xFFF59E0B))),
                  ),
                ],
              ),
            ),

          // Hardware & Safety Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF22C55E), size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Thermal Protection: FFmpeg capped at 5 CPU cores max',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SAFE MODE',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active Scan Card (if scanning or paused)
          if (activeScan != null && !activeScan.isFinished)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F1D36), Color(0xFF161622)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ACTIVE SCAN IN PROGRESS',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF818CF8)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          activeScan.status.name.toUpperCase(),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF818CF8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Short: ${activeScan.shortName ?? "video"}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Movie: ${activeScan.movieName ?? "movie"}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${activeScan.matches.length} matches found',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFF59E0B)),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ScanScreen()),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: const Text('View Scanner'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Start New Scan Primary Card
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UploadScreen()),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_to_queue, color: Color(0xFF6366F1), size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Match Scan',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Compare short clip vs movie with frame-by-frame AI analysis.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Recent Scans Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Scans',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (recentScans.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                  child: const Text('See All', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (recentScans.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.video_library_outlined, size: 40, color: Colors.white24),
                  SizedBox(height: 12),
                  Text(
                    'No scan history yet',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Select a short video and movie to start matching.',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            )
          else
            ...recentScans.map((scan) {
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scan.matches.isNotEmpty
                          ? const Color(0xFF22C55E).withOpacity(0.15)
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      scan.matches.isNotEmpty ? Icons.check_circle_outline : Icons.movie_outlined,
                      color: scan.matches.isNotEmpty ? const Color(0xFF22C55E) : Colors.white60,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    scan.shortName ?? 'Scan ${scan.id.substring(0, 6)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${scan.matches.length} matches · ${Formatters.formatDate(scan.createdAt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white30),
                  onTap: () {
                    scanService.selectScan(scan);
                    if (scan.matches.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ResultsScreen(scan: scan)),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ScanScreen()),
                      );
                    }
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}
