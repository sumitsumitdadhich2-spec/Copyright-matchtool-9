import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../api/scan_actions_api.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 1:1 Port of components/cmt/batch-verifier-panel.tsx
/// 24 FPS Minute-by-Minute Batch Verifier Panel with minute blocks, scene breakdown & rescan picker.

class BatchVerifierPanel extends StatefulWidget {
  final Scan scan;

  const BatchVerifierPanel({super.key, required this.scan});

  @override
  State<BatchVerifierPanel> createState() => _BatchVerifierPanelState();
}

class _BatchVerifierPanelState extends State<BatchVerifierPanel> {
  final Map<int, bool> _expandedMinutes = {0: true};
  int? _triggeringMinute;
  bool _triggeringAll = false;
  int? _rescanningPartIndex;
  int? _modelPickerPartIndex;
  String? _feedbackMsg;
  bool _feedbackOk = true;

  final List<Map<String, String>> _models = [
    {'id': 'gemini-2.5-flash', 'name': 'Gemini 2.5 Flash'},
    {'id': 'gemini-2.5-pro', 'name': 'Gemini 2.5 Pro'},
    {'id': 'gemini-3-flash', 'name': 'Gemini 3 Flash'},
    {'id': 'gemini-3.5-flash', 'name': 'Gemini 3.5 Flash'},
    {'id': 'gemini-3.5-flash-lite', 'name': 'Gemini 3.5 Flash-Lite'},
    {'id': 'gemini-3.1-flash-lite', 'name': 'Gemini 3.1 Flash-Lite'},
  ];

  void _toggleMinute(int minIdx) {
    setState(() {
      _expandedMinutes[minIdx] = !(_expandedMinutes[minIdx] ?? false);
    });
  }

  Future<void> _handleVerifyAll() async {
    if (_triggeringAll) return;
    setState(() {
      _triggeringAll = true;
      _feedbackMsg = null;
    });

    final scanService = context.read<ScanService>();
    try {
      final res = await ScanActionsApi.batchVerify(
        scanId: widget.scan.id,
        action: 'start_all',
      );
      if (res.statusCode == 200) {
        setState(() {
          _feedbackOk = true;
          _feedbackMsg = 'Started 24 FPS batch verification across all minute blocks.';
        });
        await scanService.batchVerifyAllMatches();
      } else {
        setState(() {
          _feedbackOk = false;
          _feedbackMsg = res.data['error']?.toString() ?? 'Failed to start batch verification';
        });
      }
    } catch (e) {
      setState(() {
        _feedbackOk = false;
        _feedbackMsg = 'Network error: $e';
      });
    } finally {
      if (mounted) setState(() => _triggeringAll = false);
    }
  }

  Future<void> _handleStop() async {
    try {
      await ScanActionsApi.batchVerify(
        scanId: widget.scan.id,
        action: 'stop',
      );
      setState(() {
        _feedbackOk = true;
        _feedbackMsg = 'Batch verification stopped.';
      });
    } catch (_) {}
  }

  Future<void> _handleVerifyMinute(int minuteIndex) async {
    if (_triggeringMinute != null) return;
    setState(() {
      _triggeringMinute = minuteIndex;
      _feedbackMsg = null;
    });

    try {
      final res = await ScanActionsApi.batchVerify(
        scanId: widget.scan.id,
        action: 'verify_minute',
        minuteIndex: minuteIndex,
      );
      if (res.statusCode == 200) {
        setState(() {
          _feedbackOk = true;
          _feedbackMsg = 'Started 24 FPS verification for Minute ${minuteIndex + 1}.';
        });
      } else {
        setState(() {
          _feedbackOk = false;
          _feedbackMsg = res.data['error']?.toString() ?? 'Failed to verify minute ${minuteIndex + 1}';
        });
      }
    } catch (e) {
      setState(() {
        _feedbackOk = false;
        _feedbackMsg = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _triggeringMinute = null);
    }
  }

  Future<void> _handleRescanScene(
    int partIndex,
    double shortStart,
    double shortEnd,
    double movieStart,
    double movieEnd,
    int chunkIndex,
    String? chosenModel,
  ) async {
    setState(() {
      _modelPickerPartIndex = null;
      _rescanningPartIndex = partIndex;
      _feedbackMsg = null;
    });

    try {
      final res = await ScanActionsApi.rescanScene(
        scanId: widget.scan.id,
        shortStart: shortStart,
        shortEnd: shortEnd,
        chunkIndex: chunkIndex,
        movieStart: movieStart,
        movieEnd: movieEnd,
        model: chosenModel,
      );

      if (res.statusCode == 200 && res.data['ok'] == true) {
        final mStart = (res.data['movieStart'] as num?)?.toDouble() ?? movieStart;
        final mEnd = (res.data['movieEnd'] as num?)?.toDouble() ?? movieEnd;
        setState(() {
          _feedbackOk = true;
          _feedbackMsg = 'Rescan Successful! Found movie ${formatSeconds(mStart)}–${formatSeconds(mEnd)} on ${res.data["model"] ?? "Gemini"}. Set as MAIN clip.';
        });
      } else {
        setState(() {
          _feedbackOk = false;
          _feedbackMsg = res.data['error']?.toString() ?? 'Rescan could not find a matching scene.';
        });
      }
    } catch (e) {
      setState(() {
        _feedbackOk = false;
        _feedbackMsg = 'Error while rescanning scene: $e';
      });
    } finally {
      if (mounted) setState(() => _rescanningPartIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    final totalDuration = widget.scan.shortDuration > 0 ? widget.scan.shortDuration : 60.0;
    final minuteCount = (totalDuration / 60.0).ceil().clamp(1, 60);

    // Summary counts
    final totalPlanned = matches.length;
    final confirmedCount = matches.where((m) => m.verified == true).length;
    final rejectedCount = matches.where((m) => m.verified == false && (m.notes ?? '').contains('rejected')).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                ),
                child: const Icon(Icons.shield_outlined, color: AppTheme.success, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Batch Minute Verifier',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '24 FPS ALL-IN-ONE',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.success),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Merges matched scenes per 1-minute window at 24 fps and verifies via Gemini.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _triggeringAll ? null : _handleVerifyAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: _triggeringAll
                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.bolt, size: 16),
                label: Text(
                  _triggeringAll ? 'Starting...' : 'Verify All',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Summary Stats Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Planned Scenes', '$totalPlanned', AppTheme.textForeground),
                Container(height: 16, width: 1, color: AppTheme.border),
                _buildStat('Confirmed (SAME)', '$confirmedCount', AppTheme.success),
                Container(height: 16, width: 1, color: AppTheme.border),
                _buildStat('Rejected', '$rejectedCount', AppTheme.destructive),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Feedback alert
          if (_feedbackMsg != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_feedbackOk ? AppTheme.success : AppTheme.destructive).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (_feedbackOk ? AppTheme.success : AppTheme.destructive).withOpacity(0.4)),
              ),
              child: Text(
                _feedbackMsg!,
                style: TextStyle(fontSize: 11, color: _feedbackOk ? AppTheme.success : AppTheme.destructive),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Minute Blocks
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: minuteCount,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, minIdx) {
              final isExpanded = _expandedMinutes[minIdx] ?? false;
              final minStart = minIdx * 60.0;
              final minEnd = (minIdx + 1) * 60.0;
              final minuteMatches = matches
                  .where((m) => m.shortStart < minEnd && m.shortEnd > minStart && (m.shortEnd - m.shortStart) >= 0.15)
                  .toList();
              final minConfirmed = minuteMatches.where((m) => m.verified == true).length;
              final isVerifyingThis = _triggeringMinute == minIdx;

              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    // Minute Header
                    InkWell(
                      onTap: () => _toggleMinute(minIdx),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                              size: 18,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Minute ${minIdx + 1} (${formatSeconds(minStart)}–${formatSeconds(minEnd)})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: minConfirmed > 0 ? AppTheme.success.withOpacity(0.15) : AppTheme.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$minConfirmed/${minuteMatches.length} scenes',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: minConfirmed > 0 ? AppTheme.success : AppTheme.textMuted,
                                ),
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: isVerifyingThis ? null : () => _handleVerifyMinute(minIdx),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: isVerifyingThis
                                  ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Verify Minute', style: TextStyle(fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Expanded Scenes List
                    if (isExpanded) ...[
                      const Divider(height: 1, color: AppTheme.border),
                      if (minuteMatches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'No detected scene candidates in this minute block.',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: minuteMatches.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                          itemBuilder: (context, sceneIdx) {
                            final m = minuteMatches[sceneIdx];
                            final isVerified = m.verified == true;
                            final isRejected = m.verified == false && (m.notes ?? '').contains('rejected');
                            final isRescanning = _rescanningPartIndex == sceneIdx;
                            final showModelPicker = _modelPickerPartIndex == sceneIdx;

                            return Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Status Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isVerified
                                                  ? AppTheme.success
                                                  : isRejected
                                                      ? AppTheme.destructive
                                                      : AppTheme.warning)
                                              .withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isVerified
                                              ? 'AI: SAME'
                                              : isRejected
                                                  ? 'AI: REJECTED'
                                                  : 'UNVERIFIED',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isVerified
                                                ? AppTheme.success
                                                : isRejected
                                                    ? AppTheme.destructive
                                                    : AppTheme.warning,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Short ${formatSeconds(m.shortStart)}–${formatSeconds(m.shortEnd)} · Movie ${formatSeconds(m.movieStart)}–${formatSeconds(m.movieEnd)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: AppTheme.textForeground,
                                          ),
                                        ),
                                      ),
                                      // Rescan Action
                                      OutlinedButton.icon(
                                        onPressed: isRescanning
                                            ? null
                                            : () {
                                                setState(() {
                                                  _modelPickerPartIndex = showModelPicker ? null : sceneIdx;
                                                });
                                              },
                                        icon: isRescanning
                                            ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                                            : const Icon(Icons.refresh, size: 12),
                                        label: const Text('Rescan', style: TextStyle(fontSize: 10)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Confidence & Continuity Notes
                                  if (m.confidence > 0 || (m.notes != null && m.notes!.isNotEmpty)) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Confidence: ${(m.confidence * 100).toStringAsFixed(0)}% · ${m.notes ?? ""}',
                                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],

                                  // Model Picker Dropdown when Rescan tapped
                                  if (showModelPicker) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.card,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Select Gemini Model for Rescan:',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: _models.map((mod) {
                                              return InkWell(
                                                onTap: () {
                                                  _handleRescanScene(
                                                    sceneIdx,
                                                    m.shortStart,
                                                    m.shortEnd,
                                                    m.movieStart,
                                                    m.movieEnd,
                                                    m.chunkIndex,
                                                    mod['id'],
                                                  );
                                                },
                                                borderRadius: BorderRadius.circular(4),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.background,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppTheme.border),
                                                  ),
                                                  child: Text(
                                                    mod['name']!,
                                                    style: const TextStyle(fontSize: 10, color: AppTheme.textForeground),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
