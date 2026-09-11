import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/storage_service.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';
import 'scan_screen.dart';
import 'results_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _editingId;
  final TextEditingController _nameController = TextEditingController();
  bool _savingName = false;

  String? _confirmDeleteId;
  bool _deleting = false;

  bool _confirmClearAll = false;
  bool _clearingAll = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditing(Scan scan) {
    setState(() {
      _editingId = scan.id;
      _nameController.text = scan.customName ?? scan.movieName ?? scan.shortName ?? '';
    });
  }

  Future<void> _saveName(String scanId) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    final storage = context.read<StorageService>();
    await storage.updateScanName(scanId, name);
    if (mounted) {
      setState(() {
        _editingId = null;
        _savingName = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan renamed successfully.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _deleteScan(String scanId) async {
    setState(() => _deleting = true);
    final storage = context.read<StorageService>();
    await storage.deleteScan(scanId);
    if (mounted) {
      setState(() {
        _deleting = false;
        _confirmDeleteId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan and local files deleted.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    setState(() => _clearingAll = true);
    final storage = context.read<StorageService>();
    final scanService = context.read<ScanService>();
    await storage.clearAllScans();
    scanService.reset();
    if (mounted) {
      setState(() {
        _clearingAll = false;
        _confirmClearAll = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All scan history and temporary files cleared.'),
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Color _getStatusColor(ScanStatus status) {
    switch (status) {
      case ScanStatus.done:
        return const Color(0xFF22C55E);
      case ScanStatus.scanning:
      case ScanStatus.chunking:
      case ScanStatus.ready:
        return const Color(0xFF38BDF8);
      case ScanStatus.verifying:
        return const Color(0xFF818CF8);
      case ScanStatus.stopped:
        return const Color(0xFFF59E0B);
      case ScanStatus.error:
        return const Color(0xFFEF4444);
      default:
        return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final scanService = context.watch<ScanService>();
    final scans = storage.savedScans;
    final activeScanId = scanService.currentScan?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text('Scan History'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF38BDF8)),
            tooltip: 'New scan',
            onPressed: () {
              scanService.reset();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Action Bar (Matching Web App)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF141416),
              border: Border(bottom: BorderSide(color: Color(0xFF27272A))),
            ),
            child: Row(
              children: [
                Text(
                  '${scans.length} Saved Scan${scans.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
                const Spacer(),
                if (scans.isNotEmpty) ...[
                  if (_confirmClearAll) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Delete all?',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _clearingAll ? null : _clearAll,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: _clearingAll
                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Yes, Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () => setState(() => _confirmClearAll = false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _confirmClearAll = true),
                      icon: const Icon(Icons.delete_sweep, size: 14, color: Color(0xFFEF4444)),
                      label: const Text('Delete All', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: const Color(0xFFEF4444).withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Scans List
          Expanded(
            child: scans.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, size: 48, color: Colors.white24),
                        SizedBox(height: 12),
                        Text('No scans yet.', style: TextStyle(color: Colors.white60, fontSize: 13)),
                        SizedBox(height: 4),
                        Text('Completed and in-progress scans will appear here.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: scans.length,
                    itemBuilder: (context, index) {
                      final scan = scans[index];
                      final isActive = scan.id == activeScanId;
                      final isEditing = _editingId == scan.id;
                      final isConfirmingDelete = _confirmDeleteId == scan.id;
                      final displayName = scan.customName?.isNotEmpty == true
                          ? scan.customName!
                          : (scan.movieName ?? scan.shortName ?? 'Untitled scan');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF1E293B) : const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF38BDF8).withOpacity(0.6)
                                : const Color(0xFF27272A),
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF38BDF8).withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
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
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Row 1: Title / Inline Rename & Status Badge
                                Row(
                                  children: [
                                    if (isEditing) ...[
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _nameController,
                                                autofocus: true,
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                decoration: const InputDecoration(
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                  hintText: 'Scan name...',
                                                  filled: true,
                                                  fillColor: Color(0xFF121214),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onSubmitted: (_) => _saveName(scan.id),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: _savingName
                                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                                  : const Icon(Icons.check, size: 16, color: Color(0xFF10B981)),
                                              onPressed: () => _saveName(scan.id),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                                              onPressed: () => setState(() => _editingId = null),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                displayName,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: isActive ? const Color(0xFF38BDF8) : Colors.white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white38),
                                              tooltip: 'Rename scan',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () => _startEditing(scan),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 8),

                                    // Status Badge (Color Coded Web App Parity)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(scan.status).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        scan.status.name.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: _getStatusColor(scan.status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Row 2: Secondary Metadata (Date, Movie Duration, Matches)
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today_outlined, size: 11, color: Colors.white38),
                                    const SizedBox(width: 4),
                                    Text(
                                      Formatters.formatDate(scan.createdAt),
                                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                                    ),
                                    if (scan.movieDuration != null) ...[
                                      const SizedBox(width: 10),
                                      const Icon(Icons.timer_outlined, size: 11, color: Colors.white38),
                                      const SizedBox(width: 4),
                                      Text(
                                        Formatters.formatDuration(scan.movieDuration!),
                                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white54),
                                      ),
                                    ],
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: scan.matches.isNotEmpty
                                            ? const Color(0xFF10B981).withOpacity(0.15)
                                            : Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${scan.matches.length} match(es)',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                          color: scan.matches.isNotEmpty ? const Color(0xFF34D399) : Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Row 3: Action & Inline Delete Confirmation
                                if (isConfirmingDelete) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Delete video & local files?',
                                            style: TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: _deleting ? null : () => _deleteScan(scan.id),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFEF4444),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: _deleting
                                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 4),
                                        TextButton(
                                          onPressed: () => setState(() => _confirmDeleteId = null),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text('Cancel', style: TextStyle(fontSize: 11, color: Colors.white70)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                                        tooltip: 'Delete scan',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => setState(() => _confirmDeleteId = scan.id),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
