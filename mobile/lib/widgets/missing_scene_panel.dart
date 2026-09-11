import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class MissingScenePanel extends StatefulWidget {
  final Scan scan;

  const MissingScenePanel({super.key, required this.scan});

  @override
  State<MissingScenePanel> createState() => _MissingScenePanelState();
}

class _MissingScenePanelState extends State<MissingScenePanel> {
  final TextEditingController _startCtrl = TextEditingController();
  final TextEditingController _endCtrl = TextEditingController();
  final List<Map<String, double>> _customGaps = [];
  bool _isScanning = false;

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _addCustomScene() {
    final s = double.tryParse(_startCtrl.text.trim());
    final e = double.tryParse(_endCtrl.text.trim());
    if (s != null && e != null && e > s) {
      setState(() {
        _customGaps.add({'start': s, 'end': e});
        _startCtrl.clear();
        _endCtrl.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid timestamps. Example: 30 to 45')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanService = context.read<ScanService>();
    final detectedGaps = widget.scan.unmappedGaps;
    final totalGaps = [...detectedGaps.map((g) => {'start': g.start, 'end': g.end}), ..._customGaps];

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
              const Row(
                children: [
                  Icon(Icons.manage_search, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Missing Scene Scanner',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (totalGaps.isEmpty ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  totalGaps.isEmpty ? '100% COVERED' : '${totalGaps.length} GAPS TO HUNT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: totalGaps.isEmpty ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Short video me jo scenes abhi tak movie me nahi mile, unhe targeted dhoondein.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 12),

          // List of gaps
          if (totalGaps.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: totalGaps.length,
                separatorBuilder: (_, __) => const Divider(height: 6, color: Colors.white10),
                itemBuilder: (context, i) {
                  final gap = totalGaps[i];
                  final dur = gap['end']! - gap['start']!;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFF59E0B), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Gap #${i + 1}: ${Formatters.formatDuration(gap['start']!)} - ${Formatters.formatDuration(gap['end']!)} (${dur.toStringAsFixed(1)}s)',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const Text('Unmapped', style: TextStyle(fontSize: 9, color: Colors.white38)),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Add custom gap input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Start (sec)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'End (sec)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addCustomScene,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Gap', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Trigger hunt button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isScanning || totalGaps.isEmpty)
                  ? null
                  : () async {
                      setState(() => _isScanning = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Targeted gap hunt started using secondary model pool...')),
                      );
                      await scanService.scanGaps();
                      setState(() => _isScanning = false);
                    },
              icon: _isScanning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.radar, size: 16),
              label: Text(
                _isScanning ? 'Hunting Missing Scenes...' : 'Hunt All Missing Scenes (${totalGaps.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
