import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class ReportPanel extends StatelessWidget {
  final Scan scan;

  const ReportPanel({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final scanService = context.read<ScanService>();
    final rep = scan.report ?? scanService.generateReport();
    final matches = scan.matches;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.assessment_outlined, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Copyright Infringement Report',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${rep.matchPercentage.toStringAsFixed(1)}% INFRINGING',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stat grid
          Row(
            children: [
              Expanded(
                child: _buildStatBlock('Short Duration', Formatters.formatDuration(rep.shortDuration)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBlock('Matched Duration', '${rep.totalMatchedSeconds.toStringAsFixed(1)}s'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatBlock('Matches Found', '${rep.totalMatchesCount} (${rep.verifiedCount} AI-ok)'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Timestamp Summary Table
          if (matches.isNotEmpty) ...[
            const Text(
              'FORENSIC TIMESTAMPS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white60, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: matches.length,
                separatorBuilder: (_, __) => const Divider(height: 8, color: Colors.white10),
                itemBuilder: (context, i) {
                  final m = matches[i];
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '#${i + 1} Short: ${Formatters.formatDuration(m.shortStart)} - ${Formatters.formatDuration(m.shortEnd)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                      Text(
                        'Movie: ${Formatters.formatDuration(m.movieStart)} - ${Formatters.formatDuration(m.movieEnd)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF38BDF8)),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Export & DMCA Notice Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final dmca = scanService.getFormattedDMCANotice();
                    Clipboard.setData(ClipboardData(text: dmca));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('DMCA Takedown Notice copied to clipboard!')),
                    );
                  },
                  icon: const Icon(Icons.gavel, size: 14),
                  label: const Text('Copy DMCA Notice', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    side: const BorderSide(color: Color(0xFFF59E0B)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final csv = scanService.exportCsv();
                    Clipboard.setData(ClipboardData(text: csv));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('CSV report copied to clipboard!')),
                    );
                  },
                  icon: const Icon(Icons.file_download_outlined, size: 14),
                  label: const Text('Export CSV', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBlock(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
