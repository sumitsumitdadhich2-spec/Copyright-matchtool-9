import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';

class BatchVerifierPanel extends StatefulWidget {
  final Scan scan;

  const BatchVerifierPanel({super.key, required this.scan});

  @override
  State<BatchVerifierPanel> createState() => _BatchVerifierPanelState();
}

class _BatchVerifierPanelState extends State<BatchVerifierPanel> {
  bool _isRunning = false;
  int _current = 0;
  int _total = 0;

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    final verified = widget.scan.verifiedMatchesCount;
    final pending = matches.length - verified;
    final scanService = context.read<ScanService>();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_outlined, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text(
                    '24fps Batch AI Verifier',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$verified / ${matches.length} VERIFIED',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Automatically extracts forensic 24fps micro-clips for every detected candidate and evaluates character movement and continuity.',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.65)),
          ),
          const SizedBox(height: 12),
          if (_isRunning) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _total > 0 ? _current / _total : null,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifying match $_current of $_total...',
              style: const TextStyle(fontSize: 11, color: Color(0xFF34D399)),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isRunning || matches.isEmpty || pending == 0)
                  ? null
                  : () async {
                      setState(() {
                        _isRunning = true;
                        _total = matches.length;
                        _current = 0;
                      });
                      await scanService.batchVerifyAllMatches(
                        onProgress: (c, t) {
                          if (mounted) setState(() { _current = c; _total = t; });
                        },
                      );
                      if (mounted) setState(() => _isRunning = false);
                    },
              icon: _isRunning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.playlist_add_check, size: 18),
              label: Text(
                pending == 0 && matches.isNotEmpty
                    ? 'All Matches Verified'
                    : 'Verify All Candidates ($pending Pending)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
                disabledBackgroundColor: Colors.white10,
                disabledForegroundColor: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
