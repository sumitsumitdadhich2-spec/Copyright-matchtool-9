import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/scan_usage.dart';

class ScanUsageReportWidget extends StatelessWidget {
  final Scan scan;

  const ScanUsageReportWidget({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final usage = ScanUsageSummary.compute(scan);

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.query_stats, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Gemini AI Request & Quota Audit',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Vastav Me Kaam Hua: ${usage.effectiveRequests}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Actual quota usage vs auto-retried error breakdown (Same as Web App)',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 12),

          // 4 Metric cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Effective Work',
                  '${usage.effectiveRequests}',
                  'Billed Requests',
                  const Color(0xFF10B981),
                  Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  'Auto-Retries',
                  '${usage.totalErrors}',
                  'Free (No Cost)',
                  const Color(0xFFF59E0B),
                  Icons.replay,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  '24fps Verifier',
                  '${usage.byStage['verifier'] ?? 0}',
                  '500 RPD Quota',
                  const Color(0xFF38BDF8),
                  Icons.shield_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Models breakdown table
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
                const Text(
                  'MODEL BREAKDOWN (TOKENS & REQUESTS)',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white60, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                _buildModelRow('gemini-3.7-flash', usage.mainModels['gemini37'] ?? 0, 'Chunk Mapper (5 RPM / 20 RPD)'),
                const Divider(height: 8, color: Colors.white10),
                _buildModelRow('gemini-3.5-flash-lite', usage.byStage['verifier'] ?? 0, '24fps Verifier (15 RPM / 500 RPD)'),
                if ((usage.mainModels['gemini38'] ?? 0) > 0) ...[
                  const Divider(height: 8, color: Colors.white10),
                  _buildModelRow('gemini-3.8-flash', usage.mainModels['gemini38'] ?? 0, 'Deep Forensic Analysis'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String val, String sub, Color col, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: col.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 9, color: col, fontWeight: FontWeight.bold)),
              Icon(icon, color: col, size: 12),
            ],
          ),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: col)),
          Text(sub, style: const TextStyle(fontSize: 8, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildModelRow(String name, int count, String desc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            Text(desc, style: const TextStyle(fontSize: 9, color: Colors.white54)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$count calls', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
        ),
      ],
    );
  }
}
