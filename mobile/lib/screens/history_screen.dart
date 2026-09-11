import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/storage_service.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';
import 'scan_screen.dart';
import 'results_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final scanService = context.read<ScanService>();
    final scans = storage.savedScans;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
      ),
      body: scans.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off, size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text('No past scans found', style: TextStyle(color: Colors.white60)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: scans.length,
              itemBuilder: (context, index) {
                final scan = scans[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getStatusColor(scan.status).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                scan.status.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(scan.status),
                                ),
                              ),
                            ),
                            Text(
                              Formatters.formatDate(scan.createdAt),
                              style: const TextStyle(fontSize: 11, color: Colors.white54),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          scan.shortName ?? 'Unknown Short Video',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'vs ${scan.movieName ?? "Unknown Movie"}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${scan.matches.length} matches',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              tooltip: 'Delete scan',
                              onPressed: () {
                                _confirmDelete(context, storage, scan);
                              },
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
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
                              child: const Text('Open'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Color _getStatusColor(ScanStatus status) {
    switch (status) {
      case ScanStatus.done:
        return const Color(0xFF22C55E);
      case ScanStatus.scanning:
      case ScanStatus.chunking:
        return const Color(0xFF6366F1);
      case ScanStatus.error:
        return const Color(0xFFEF4444);
      case ScanStatus.stopped:
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }

  void _confirmDelete(BuildContext context, StorageService storage, Scan scan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Scan?'),
        content: Text('Are you sure you want to delete scan record for "${scan.shortName}" and all associated chunk files?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await storage.deleteScan(scan.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
