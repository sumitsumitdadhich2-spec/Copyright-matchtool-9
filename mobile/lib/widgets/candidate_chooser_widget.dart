import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../services/storage_service.dart';
import '../services/session_service.dart';
import '../utils/candidate_pick.dart';
import '../utils/formatters.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/candidate-chooser.tsx
/// Candidate browser shown under a clip that has alternative movie windows.
/// Allows cycling through candidate windows, previewing alternative windows,
/// setting a candidate as MAIN clip, or resetting to the AI verdict.

class CandidateOption {
  final int index;
  final String groupId;
  final bool isMain;
  final bool isUserPick;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final String? model;
  final String state; // 'main' | 'confirmed' | 'rejected' | 'unverified' | 'pending' | 'checking'
  final bool viaRescan;
  final String? origin;

  CandidateOption({
    required this.index,
    required this.groupId,
    required this.isMain,
    required this.isUserPick,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    this.model,
    required this.state,
    this.viaRescan = false,
    this.origin,
  });
}

class CandidateChooserWidget extends StatefulWidget {
  final Scan scan;
  final List<CandidateOption> options;
  final int? viewIdx;
  final ValueChanged<int?> onView;
  final bool compact;

  const CandidateChooserWidget({
    super.key,
    required this.scan,
    required this.options,
    required this.viewIdx,
    required this.onView,
    this.compact = false,
  });

  @override
  State<CandidateChooserWidget> createState() => _CandidateChooserWidgetState();
}

class _CandidateChooserWidgetState extends State<CandidateChooserWidget> {
  bool _busy = false;
  String? _error;

  void _step(int dir) {
    final total = widget.options.length;
    if (total == 0) return;

    if (total == 1) {
      if (widget.viewIdx == null && !widget.options[0].isMain) {
        widget.onView(0);
      } else {
        widget.onView(null);
      }
      return;
    }

    final mainIdx = widget.options.indexWhere((o) => o.isMain);
    final viewing = widget.viewIdx == null
        ? null
        : widget.options[widget.viewIdx!.clamp(0, total - 1)];
    final pos = viewing != null
        ? widget.options.indexOf(viewing)
        : (mainIdx >= 0 ? mainIdx : 0);

    final next = (pos + dir + total) % total;
    final o = widget.options[next];
    widget.onView(o.isMain ? null : next);
  }

  Future<void> _makeMain(CandidateOption viewing) async {
    if (viewing.isMain) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final scanService = context.read<ScanService>();
      final storageService = context.read<StorageService>();
      final session = SessionService.verifySessionToken(null); // or active session

      // Update candidate group in scan
      final g = widget.scan.candidateGroups.where((grp) => grp.id == viewing.groupId).firstOrNull;
      if (g != null) {
        g.userPickId = 'cand-${viewing.chunkIndex}-${viewing.index}';
        g.confirmedIndex = viewing.index;
        g.confirmedViaRescan = viewing.viaRescan;
        g.status = 'confirmed';
      }

      // Re-apply matches
      CandidatePickUtils.applyGroupMatches(widget.scan);
      await storageService.updateScan(widget.scan);
      scanService.notifyListeners();

      widget.onView(null);
    } catch (e) {
      setState(() => _error = 'Network error — dobara try karo ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetToAi(CandidateOption picked) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final scanService = context.read<ScanService>();
      final storageService = context.read<StorageService>();

      final g = widget.scan.candidateGroups.where((grp) => grp.id == picked.groupId).firstOrNull;
      if (g != null) {
        g.userPickId = null;
      }

      CandidatePickUtils.applyGroupMatches(widget.scan);
      await storageService.updateScan(widget.scan);
      scanService.notifyListeners();

      widget.onView(null);
    } catch (e) {
      setState(() => _error = 'Failed to reset: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    if (options.isEmpty) return const SizedBox.shrink();

    final total = options.length;
    final mainIdx = options.indexWhere((o) => o.isMain);
    final mainOpt = mainIdx >= 0 ? options[mainIdx] : null;
    final viewing = widget.viewIdx == null
        ? null
        : options[widget.viewIdx!.clamp(0, total - 1)];
    final pos = viewing != null
        ? options.indexOf(viewing)
        : (mainIdx >= 0 ? mainIdx : 0);

    final renderRunning = widget.scan.status == ScanStatus.scanning;
    final choiceLocked = renderRunning;
    final choiceLockedReason = renderRunning
        ? 'Render/Scan chal raha hai — finish hone ke baad main clip badlo'
        : null;

    final hasMultiple = total > 1 || (total == 1 && !options[0].isMain);
    final userPicked = options.any((o) => o.isUserPick);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: EdgeInsets.all(widget.compact ? 8 : 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.35),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              const Icon(Icons.star, size: 14, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                '$total candidate${total == 1 ? "" : "s"} for this clip',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
              ),
              const SizedBox(width: 8),

              // Rescanned or State Badge
              if (viewing != null && (viewing.viaRescan || viewing.origin == 'rescan'))
                _buildBadge('🔄 Rescanned (User Review)', const Color(0xFF6366F1))
              else if (viewing == null && mainOpt != null && (mainOpt.viaRescan || mainOpt.origin == 'rescan'))
                _buildBadge('🔄 Rescanned Main', const Color(0xFF6366F1))
              else if (viewing != null)
                _buildStateBadge(viewing.state)
              else if (mainOpt != null)
                _buildStateBadge('main'),

              const Spacer(),
              Text(
                viewing != null ? 'Candidate ${pos + 1} of $total' : 'Main (${pos + 1}/$total)',
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Details text
          if (viewing != null)
            Text(
              'short ${formatSeconds(viewing.shortStart)}–${formatSeconds(viewing.shortEnd)} (${(viewing.shortEnd - viewing.shortStart).toStringAsFixed(1)}s) · movie ${formatSeconds(viewing.movieStart)}–${formatSeconds(viewing.movieEnd)} · chunk ${viewing.chunkIndex} · ${viewing.model ?? "Gemini"}${viewing.viaRescan || viewing.origin == "rescan" ? " · 🔄 rescan" : ""}',
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
            )
          else if (mainOpt != null)
            Text(
              'showing MAIN — short ${formatSeconds(mainOpt.shortStart)}–${formatSeconds(mainOpt.shortEnd)} (${(mainOpt.shortEnd - mainOpt.shortStart).toStringAsFixed(1)}s) · movie ${formatSeconds(mainOpt.movieStart)}–${formatSeconds(mainOpt.movieEnd)}${mainOpt.viaRescan || mainOpt.origin == "rescan" ? " · 🔄 rescan" : mainOpt.isUserPick ? " · your choice" : ""}',
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
            ),
          const SizedBox(height: 8),

          // Action Buttons Row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: (!hasMultiple || _busy) ? null : () => _step(-1),
                icon: const Icon(Icons.chevron_left, size: 14),
                label: const Text('Prev candidate', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              OutlinedButton.icon(
                onPressed: (!hasMultiple || _busy) ? null : () => _step(1),
                icon: const Icon(Icons.chevron_right, size: 14),
                label: const Text('Next candidate', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (viewing != null && !viewing.isMain)
                OutlinedButton(
                  onPressed: _busy ? null : () => widget.onView(null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Back to main', style: TextStyle(fontSize: 11)),
                ),
              ElevatedButton.icon(
                onPressed: (viewing == null || viewing.isMain || _busy || choiceLocked)
                    ? null
                    : () => _makeMain(viewing),
                icon: _busy
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check, size: 14),
                label: const Text('Make this the main clip', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.primaryForeground,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (userPicked)
                OutlinedButton.icon(
                  onPressed: (_busy || choiceLocked)
                      ? null
                      : () {
                          final picked = options.firstWhere((o) => o.isUserPick);
                          _resetToAi(picked);
                        },
                  icon: const Icon(Icons.undo, size: 14),
                  label: const Text('Reset to AI', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),

          if (choiceLockedReason != null) ...[
            const SizedBox(height: 4),
            Text(
              'Candidate dekh sakte ho; $choiceLockedReason.',
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(fontSize: 10, color: AppTheme.destructive),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStateBadge(String state) {
    Color col;
    String text;
    switch (state) {
      case 'main':
        col = AppTheme.success;
        text = 'MAIN clip';
        break;
      case 'confirmed':
        col = AppTheme.success;
        text = 'AI: SAME';
        break;
      case 'rejected':
        col = AppTheme.destructive;
        text = 'AI: rejected';
        break;
      case 'unverified':
        col = AppTheme.warning;
        text = 'unverified';
        break;
      case 'checking':
        col = AppTheme.primary;
        text = 'checking';
        break;
      default:
        col = AppTheme.textMuted;
        text = 'not checked yet';
    }
    return _buildBadge(text, col);
  }
}
