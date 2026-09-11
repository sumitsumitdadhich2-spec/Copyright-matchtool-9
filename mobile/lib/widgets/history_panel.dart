import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/storage_service.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';
import '../screens/scan_screen.dart';
import '../screens/results_screen.dart';

class HistoryPanelWidget extends StatefulWidget {
  final VoidCallback? onNewScan;

  const HistoryPanelWidget({super.key, this.onNewScan});

  @override
  State<HistoryPanelWidget> createState() => _HistoryPanelWidgetState();
}

class _HistoryPanelWidgetState extends State<HistoryPanelWidget> {
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
        const SnackBar(content: Text('Scan renamed successfully.'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _deleteScan(String scanId) async {
    setState(() => _deleting = true);
    final storage = context.read<StorageService>();
    final scanService = context.read<ScanService>();
    if (scanService.currentScan?.id == scanId) {
      scanService.reset();
    }
    await storage.deleteScan(scanId);
    if (mounted) {
      setState(() {
        _deleting = false;
        _confirmDeleteId = null;
      });
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

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF27272A)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Matching HistoryPanel from Web App)
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 18, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              const Text(
                'Scan History',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (scans.isNotEmpty) ...[
                if (_confirmClearAll) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Delete all?',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _clearingAll ? null : _clearAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: _clearingAll
                                ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Yes', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _confirmClearAll = false),
                          child: const Text('Cancel', style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _confirmClearAll = true),
                    icon: const Icon(Icons.delete_sweep, size: 12, color: Color(0xFFEF4444)),
                    label: const Text('Delete All', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
              ],
              OutlinedButton.icon(
                onPressed: () {
                  if (widget.onNewScan != null) {
                    widget.onNewScan!();
                  } else {
                    scanService.reset();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
                  }
                },
                icon: const Icon(Icons.add, size: 12),
                label: const Text('New scan', style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (scans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No scans yet.', style: TextStyle(fontSize: 12, color: Colors.white38)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scans.length,
              itemBuilder: (context, i) {
                final scan = scans[i];
                final isActive = scan.id == activeScanId;
                final isEditing = _editingId == scan.id;
                final isConfirmingDelete = _confirmDeleteId == scan.id;
                final displayName = scan.customName?.isNotEmpty == true
                    ? scan.customName!
                    : (scan.movieName ?? scan.shortName ?? 'Untitled scan');

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF1E293B) : const Color(0xFF121214),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? const Color(0xFF38BDF8).withOpacity(0.5) : const Color(0xFF27272A),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      scanService.selectScan(scan);
                      if (scan.matches.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ResultsScreen(scan: scan)),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            hintText: 'Scan name...',
                                            filled: true,
                                            fillColor: Color(0xFF18181B),
                                            border: OutlineInputBorder(),
                                          ),
                                          onSubmitted: (_) => _saveName(scan.id),
                                        ),
                                      ),
                                      IconButton(
                                        icon: _savingName
                                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.check, size: 14, color: Color(0xFF10B981)),
                                        onPressed: () => _saveName(scan.id),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 14, color: Colors.white54),
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
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isActive ? const Color(0xFF38BDF8) : Colors.white,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 12, color: Colors.white38),
                                        tooltip: 'Rename scan',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _startEditing(scan),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(scan.status).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  scan.status.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(scan.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                Formatters.formatDate(scan.createdAt),
                                style: const TextStyle(fontSize: 10, color: Colors.white54),
                              ),
                              if (scan.movieDuration != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  Formatters.formatDuration(scan.movieDuration!),
                                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white54),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                '${scan.matches.length} match(es)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: scan.matches.isNotEmpty ? const Color(0xFF34D399) : Colors.white54,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isConfirmingDelete) ...[
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _deleting ? null : () => _deleteScan(scan.id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: _deleting
                                            ? const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                            : const Text('Delete', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setState(() => _confirmDeleteId = null),
                                      child: const Text('Cancel', style: TextStyle(fontSize: 9, color: Colors.white70)),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 14, color: Colors.white38),
                                  tooltip: 'Delete scan',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setState(() => _confirmDeleteId = scan.id),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
