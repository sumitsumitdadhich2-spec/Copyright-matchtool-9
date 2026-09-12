import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import 'video_player_widget.dart';

/// 1:1 Port of components/cmt/candidates-panel.tsx
/// Candidates explorer panel showing candidate groups, status badges, origins, rescan outcomes & movie preview.

class CandidatesPanel extends StatefulWidget {
  final Scan scan;

  const CandidatesPanel({super.key, required this.scan});

  @override
  State<CandidatesPanel> createState() => _CandidatesPanelState();
}

class _CandidatesPanelState extends State<CandidatesPanel> {
  bool _isOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _fmtTime(double seconds) {
    final s = seconds.floor();
    final m = s ~/ 60;
    final remS = s % 60;
    return '${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.scan.candidateGroups ?? [];
    if (groups.isEmpty) return const SizedBox.shrink();

    final totalCandidates = groups.fold<int>(0, (n, g) => n + (g.candidates?.length ?? 0));
    final q = _searchQuery.trim().toLowerCase();

    final filteredGroups = groups.where((g) {
      if (q.isEmpty) return true;
      final str = '${_fmtTime(g.shortStart)} ${_fmtTime(g.shortEnd)} ${g.status} ${g.origin ?? ""} ${g.candidates?.map((c) => "${c.chunkIndex} ${_fmtTime(c.movieStart)}").join(" ") ?? ""}'.toLowerCase();
      return str.contains(q);
    }).toList()..sort((a, b) => a.shortStart.compareTo(b.shortStart));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.gps_fixed, size: 16, color: AppTheme.destructive),
                const SizedBox(width: 8),
                const Text('Match Candidates Explorer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${groups.length} groups · $totalCandidates candidates',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _isOpen = !_isOpen),
                  icon: Icon(_isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16),
                  label: Text(_isOpen ? 'Collapse' : 'Expand All', style: const TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Candidate details & live verification status are also integrated right into the Match Report Table.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),

            if (_isOpen) ...[
              const SizedBox(height: 12),
              // Search field
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search candidate groups by timestamp or chunk...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Candidate group cards
              ...filteredGroups.map((g) => _buildGroupCard(g)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(CandidateGroup g) {
    (String label, Color bg, Color text) badge;
    switch (g.status) {
      case 'confirmed':
        badge = ('Confirmed', AppTheme.success.withOpacity(0.15), AppTheme.success);
        break;
      case 'verifying':
        badge = ('Verifying 24fps', AppTheme.primary.withOpacity(0.15), AppTheme.primary);
        break;
      case 'rescanning':
        badge = ('Rescanning', AppTheme.warning.withOpacity(0.15), AppTheme.warning);
        break;
      case 'rejected':
        badge = ('Rejected (final)', AppTheme.destructive.withOpacity(0.15), AppTheme.destructive);
        break;
      case 'unverified':
        badge = ('Unverified', AppTheme.warning.withOpacity(0.15), AppTheme.warning);
        break;
      default:
        badge = ('Pending verify', AppTheme.secondary, AppTheme.textMuted);
    }

    final candidates = g.candidates ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Short ${_fmtTime(g.shortStart)} – ${_fmtTime(g.shortEnd)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppTheme.textForeground),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badge.$2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge.$1,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badge.$3),
                ),
              ),
              if (g.origin != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    g.origin ?? '',
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Candidates list
          ...candidates.asMap().entries.map((entry) {
            final idx = entry.key;
            final c = entry.value;
            return _buildCandidateRow(g, c, idx);
          }),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(CandidateGroup g, CandidateEntry c, int index) {
    final previewStart = g.confirmedViaRescan == true && g.confirmedIndex == index && c.rescanMovieStart != null
        ? c.rescanMovieStart!
        : c.movieStart;

    final isWinner = g.status == 'confirmed' && g.confirmedIndex == index;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.secondary.withOpacity(0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${index + 1} Movie ${_fmtTime(c.movieStart)} – ${_fmtTime(c.movieEnd)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
              const SizedBox(width: 8),
              Text(
                'chunk ${c.chunkIndex}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
              ),
              const Spacer(),
              if (isWinner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, size: 12, color: AppTheme.success),
                      const SizedBox(width: 4),
                      Text(
                        g.confirmedViaRescan == true ? 'SAME (rescan)' : 'SAME',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.success),
                      ),
                    ],
                  ),
                )
              else if (c.verdict == 'different')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.destructive.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'DIFFERENT',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.destructive),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'pending',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Found by ${c.model}${c.verifierModel != null ? " · verified by ${c.verifierModel}" : ""}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (c.verifierReason != null && c.verifierReason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '“${c.verifierReason}”',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textForeground),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: AppTheme.card,
                builder: (ctx) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Movie Preview at ${_fmtTime(previewStart)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 220,
                        child: VideoPlayerWidget(
                          videoUrl: '/api/scans/${widget.scan.id}/media?kind=movie',
                          initialPosition: previewStart,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            icon: const Icon(Icons.play_arrow, size: 14, color: AppTheme.primary),
            label: Text('Preview at ${_fmtTime(previewStart)}', style: const TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
