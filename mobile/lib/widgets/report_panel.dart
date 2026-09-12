import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'scan_timing_report.dart';
import 'scan_usage_report.dart';

/// 1:1 Port of components/cmt/report-panel.tsx
/// Match Report & Audit Panel with filters, search, candidate verification status, and forensic details.

class ReportPanel extends StatefulWidget {
  final Scan scan;

  const ReportPanel({super.key, required this.scan});

  @override
  State<ReportPanel> createState() => _ReportPanelState();
}

class _ReportPanelState extends State<ReportPanel> {
  String _filterMode = 'all'; // all, confirmed, rejected, rescan, verifying
  String _searchQuery = '';
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    final groups = widget.scan.candidateGroups;

    // Filter matches
    final filtered = matches.asMap().entries.where((entry) {
      final m = entry.value;
      if (_filterMode == 'confirmed' && !(m.verified || m.batchVerified == 'confirmed')) return false;
      if (_filterMode == 'rejected' && !(m.rejected || m.batchVerified == 'rejected')) return false;
      if (_filterMode == 'rescan' && !(m.viaRescan || m.origin == 'rescan')) return false;
      if (_filterMode == 'verifying' && m.batchVerified != 'verifying') return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final text = '${formatSeconds(m.shortStart)} ${formatSeconds(m.movieStart)} ${m.model} ${m.reason ?? ""}'.toLowerCase();
        if (!text.contains(q)) return false;
      }
      return true;
    }).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Match Report & Verification Audit',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${matches.where((m) => m.verified || m.batchVerified == "confirmed").length}/${matches.length} confirmed',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          // Filter pills + Search
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search timestamps or reason...',
                      hintStyle: const TextStyle(fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 14),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                    ),
                    style: const TextStyle(fontSize: 11),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'All (${matches.length})'),
                _buildFilterChip('confirmed', 'Confirmed (${matches.where((m) => m.verified || m.batchVerified == "confirmed").length})'),
                _buildFilterChip('rejected', 'Rejected (${matches.where((m) => m.rejected || m.batchVerified == "rejected").length})'),
                _buildFilterChip('rescan', 'Rescan (${matches.where((m) => m.viaRescan || m.origin == "rescan").length})'),
                _buildFilterChip('verifying', 'Verifying'),
              ],
            ),
          ),

          const SizedBox(height: 10),
          // Matches list
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: const Text('No matches match the selected criteria.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            )
          else
            ...filtered.map((entry) {
              final idx = entry.key;
              final m = entry.value;
              final isExpanded = _expandedIndex == idx;
              final isConfirmed = m.verified || m.batchVerified == 'confirmed';
              final isRejected = m.rejected || m.batchVerified == 'rejected';

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppTheme.background.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isConfirmed
                        ? AppTheme.success.withOpacity(0.4)
                        : isRejected
                            ? AppTheme.destructive.withOpacity(0.4)
                            : AppTheme.border,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Row(
                        children: [
                          Text(
                            'Short ${formatSeconds(m.shortStart)}–${formatSeconds(m.shortEnd)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const Text(' ➔ ', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                          Text(
                            'Movie ${formatSeconds(m.movieStart)}–${formatSeconds(m.movieEnd)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Chunk ${m.chunkIndex} · ${m.model} · Conf: ${((m.confidence ?? 0.8) * 100).toInt()}%',
                        style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isConfirmed ? AppTheme.success : isRejected ? AppTheme.destructive : AppTheme.warning).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isConfirmed
                                  ? 'CONFIRM YES'
                                  : isRejected
                                      ? 'REJECTED'
                                      : 'UNVERIFIED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isConfirmed
                                    ? AppTheme.success
                                    : isRejected
                                        ? AppTheme.destructive
                                        : AppTheme.warning,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16),
                        ],
                      ),
                      onTap: () => setState(() => _expandedIndex = isExpanded ? null : idx),
                    ),
                    if (isExpanded) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            if (m.reason != null && m.reason!.isNotEmpty)
                              Text('AI Evidence: ${m.reason}', style: const TextStyle(fontSize: 11, color: AppTheme.textForeground)),
                            const SizedBox(height: 4),
                            Text('Origin: ${m.origin ?? "gemini_scan"} · Model: ${m.model}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),

          const SizedBox(height: 12),
          // Usage & Timing Sub-reports
          ScanUsageReport(scan: widget.scan),
          const SizedBox(height: 12),
          ScanTimingReport(scan: widget.scan),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String mode, String label) {
    final isSel = _filterMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _filterMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSel ? AppTheme.primary.withOpacity(0.2) : AppTheme.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSel ? AppTheme.primary : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? AppTheme.primary : AppTheme.textMuted),
          ),
        ),
      ),
    );
  }
}
