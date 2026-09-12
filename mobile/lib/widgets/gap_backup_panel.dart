import 'dart:async';
import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../services/gap_backup_service.dart';
import 'video_player_widget.dart';

/// 1:1 Port of components/cmt/gap-backup-panel.tsx
/// Missing-scene finder with model picker, phases tracker, dual synchronized video candidate review & live Gemini request logs.

const List<Map<String, String>> GAP_MODELS = [
  {'id': 'gemini-3.7-flash', 'name': 'Gemini 3.7 Flash', 'rpm': '1000', 'rpd': '10000'},
  {'id': 'gemini-3.8-flash', 'name': 'Gemini 3.8 Flash', 'rpm': '1000', 'rpd': '10000'},
  {'id': 'gemini-3.6-flash', 'name': 'Gemini 3.6 Flash', 'rpm': '1000', 'rpd': '10000'},
  {'id': 'gemini-2.5-flash', 'name': 'Gemini 2.5 Flash', 'rpm': '1000', 'rpd': '10000'},
];

const List<Map<String, String>> PHASES = [
  {'key': 'cutting', 'label': 'Prepare clips'},
  {'key': 'uploading', 'label': 'Upload'},
  {'key': 'searching', 'label': 'Chunk batches'},
  {'key': 'awaiting_review', 'label': 'Review'},
  {'key': 'done', 'label': 'Done'},
];

class GapBackupPanel extends StatefulWidget {
  final Scan scan;

  const GapBackupPanel({super.key, required this.scan});

  @override
  State<GapBackupPanel> createState() => _GapBackupPanelState();
}

class _GapBackupPanelState extends State<GapBackupPanel> {
  bool _busy = false;
  String? _error;
  bool _showModelPicker = false;
  List<String> _selectedModels = ['gemini-3.7-flash', 'gemini-3.8-flash', 'gemini-3.6-flash'];

  String _fmtTime(double seconds) {
    final s = seconds.floor();
    final m = s ~/ 60;
    final remS = s % 60;
    return '${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}';
  }

  void _toggleModel(String id) {
    setState(() {
      if (_selectedModels.contains(id)) {
        _selectedModels.remove(id);
      } else {
        _selectedModels.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shortDur = widget.scan.shortDuration;
    final matches = widget.scan.matches;

    // Calculate covered vs gap segments
    double matchedSecs = 0.0;
    for (final m in matches) {
      matchedSecs += (m.shortEnd - m.shortStart).clamp(0.0, shortDur);
    }
    final gapSecs = (shortDur - matchedSecs).clamp(0.0, shortDur);
    final coveragePct = ((matchedSecs / (shortDur > 0 ? shortDur : 1.0)) * 100.0).clamp(0.0, 100.0);

    final rawState = widget.scan.gapBackup;
    final stateStatus = rawState?['status'] as String? ?? 'idle';
    final candidates = (rawState?['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final pendingCandidates = candidates.where((c) => c['review'] == 'pending').toList();
    final requests = (rawState?['requests'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final running = ['cutting', 'uploading', 'searching'].contains(stateStatus);
    final currentPhase = PHASES.indexWhere((p) => p['key'] == stateStatus);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18, color: AppTheme.warning),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manual missing-scene finder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('Initial minute finder se alag, transparent 24 fps search', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${coveragePct.toStringAsFixed(1)}% covered',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.warning),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${gapSecs.toStringAsFixed(1)}s missing',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                ),
              ],
            ),

            // Model Selection Controls
            if (!running) ...[
              const SizedBox(height: 12),
              Container(
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
                          'Targeted AI Models (${_selectedModels.length} selected):',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => setState(() => _showModelPicker = !_showModelPicker),
                          child: Text(
                            _showModelPicker ? 'Hide Options ▲' : 'Customize Models ▼',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => setState(() => _selectedModels = GAP_MODELS.map((m) => m['id']!).toList()),
                          child: const Text('Select All', style: TextStyle(fontSize: 11, color: AppTheme.primary)),
                        ),
                        const SizedBox(width: 6),
                        const Text('·', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => setState(() => _selectedModels = ['gemini-3.7-flash', 'gemini-3.8-flash', 'gemini-3.6-flash']),
                          child: const Text('Reset Default', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        ),
                      ],
                    ),
                    if (_showModelPicker) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: GAP_MODELS.map((m) {
                          final isChecked = _selectedModels.contains(m['id']);
                          return FilterChip(
                            label: Text('${m['name']} (${m['rpm']} RPM)', style: const TextStyle(fontSize: 11)),
                            selected: isChecked,
                            onSelected: (_) => _toggleModel(m['id']!),
                            selectedColor: AppTheme.primary.withOpacity(0.2),
                            checkmarkColor: AppTheme.primary,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            // Actions Row
            Row(
              children: [
                if (!running)
                  ElevatedButton.icon(
                    onPressed: _busy || pendingCandidates.isNotEmpty || _selectedModels.isEmpty
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            // Trigger Gap Finder
                            await GapBackupService.startGapBackup(widget.scan.id, _selectedModels);
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: _busy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.search, size: 14),
                    label: Text(
                      stateStatus == 'idle' ? 'Find missing scenes (${_selectedModels.length} models)' : 'Retry unresolved ranges (${_selectedModels.length} models)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await GapBackupService.stopGapBackup(widget.scan.id);
                            if (mounted) setState(() => _busy = false);
                          },
                    icon: const Icon(Icons.stop, size: 14),
                    label: const Text('Stop finder', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive),
                  ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Manual only · suggested movie chunks only · maximum 4 parallel',
                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),

            if (pendingCandidates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Pehle ${pendingCandidates.length} pending candidate(s) Accept/Reject karein; uske baad unresolved ranges Retry kar sakte hain.',
                style: const TextStyle(fontSize: 11, color: AppTheme.warning),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.destructive)),
            ],

            // Phase Progress Strip
            if (stateStatus != 'idle') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: PHASES.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final phase = entry.value;
                          final active = phase['key'] == stateStatus;
                          final passed = currentPhase >= 0 && idx < currentPhase;

                          return Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: passed ? AppTheme.success : active ? AppTheme.primary : AppTheme.secondary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  passed ? Icons.check : active && running ? Icons.sync : Icons.circle,
                                  size: 12,
                                  color: (passed || active) ? Colors.black : AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                phase['label']!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                                  color: active ? AppTheme.textForeground : AppTheme.textMuted,
                                ),
                              ),
                              if (idx < PHASES.length - 1)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  width: 16,
                                  height: 1,
                                  color: AppTheme.border,
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rawState?['progress'] as String? ?? stateStatus,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textForeground),
                    ),
                  ],
                ),
              ),
            ],

            // Pending Candidate Review Cards
            if (pendingCandidates.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('SIDE-BY-SIDE CANDIDATE REVIEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              ...pendingCandidates.map((c) => _buildReviewCandidateCard(c)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCandidateCard(Map<String, dynamic> candidate) {
    final candId = candidate['id'] as String? ?? '';
    final chunkIdx = (candidate['chunkIndex'] as num?)?.toInt() ?? 0;
    final model = candidate['model'] as String? ?? 'Gemini';
    final shortStart = (candidate['shortStart'] as num?)?.toDouble() ?? 0.0;
    final shortEnd = (candidate['shortEnd'] as num?)?.toDouble() ?? 0.0;
    final movieStart = (candidate['movieStart'] as num?)?.toDouble() ?? 0.0;
    final movieEnd = (candidate['movieEnd'] as num?)?.toDouble() ?? 0.0;
    final reason = candidate['reason'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('NEEDS YOUR REVIEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.warning)),
              ),
              const SizedBox(width: 8),
              Text('chunk ${chunkIdx + 1} · $model', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted)),
            ],
          ),
          const SizedBox(height: 10),

          // Dual Preview
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Short ${_fmtTime(shortStart)}–${_fmtTime(shortEnd)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 120,
                      child: VideoPlayerWidget(videoUrl: '/api/scans/${widget.scan.id}/media?kind=short', initialPosition: shortStart),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Movie ${_fmtTime(movieStart)}–${_fmtTime(movieEnd)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 120,
                      child: VideoPlayerWidget(videoUrl: '/api/scans/${widget.scan.id}/media?kind=movie', initialPosition: movieStart),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reason.isNotEmpty)
            Text('Gemini evidence: $reason', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 10),

          // Accept / Reject
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  await GapBackupService.acceptCandidate(widget.scan.id, candId);
                  setState(() {});
                },
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Accept match', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await GapBackupService.rejectCandidate(widget.scan.id, candId);
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 14, color: AppTheme.destructive),
                label: const Text('Reject', style: TextStyle(fontSize: 11, color: AppTheme.destructive)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
