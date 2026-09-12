import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../api/scans_api.dart';

/// 1:1 Port of components/cmt/chunk-results-panel.tsx
/// Chunk timeline panel showing matches per minute, raw AI outputs, multi-segment tabs, and single chunk retry.

const int CHUNK_SECONDS = 60;

class ChunkResultsPanel extends StatefulWidget {
  final Scan scan;
  final VoidCallback? onRefresh;

  const ChunkResultsPanel({super.key, required this.scan, this.onRefresh});

  @override
  State<ChunkResultsPanel> createState() => _ChunkResultsPanelState();
}

class _ChunkResultsPanelState extends State<ChunkResultsPanel> {
  int? _selectedSeg;

  String _fmtTime(double seconds) {
    final s = seconds.floor();
    final m = s ~/ 60;
    final remS = s % 60;
    return '${m.toString().padLeft(2, '0')}:${remS.toString().padLeft(2, '0')}';
  }

  List<ChunkState> _chunksForSegment(Scan scan, int segIdx) {
    final segs = scan.shortSegments;
    if (segs == null || segs.isEmpty) return scan.chunks;
    if (segIdx == (scan.currentShortSegment ?? 0)) return scan.chunks;
    if (segIdx < segs.length) return segs[segIdx].chunks;
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final segs = widget.scan.shortSegments ?? [];
    final multi = segs.length > 1;
    final activeSeg = widget.scan.currentShortSegment ?? 0;
    final segIdx = _selectedSeg ?? activeSeg;

    final chunks = _chunksForSegment(widget.scan, segIdx);
    final visible = chunks.where((c) => c.status != 'pending' || c.matches.isNotEmpty || c.rawOutputs.isNotEmpty).toList();

    if (visible.isEmpty && !multi) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text('Chunk Timeline — Matches Per Minute', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                if (multi) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'short min ${segIdx + 1}/${segs.length}',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.primary),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${visible.length}/${widget.scan.chunkCount} chunk(s)',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Har movie minute ke liye ek hi AI call: short video + wo chunk. Matched lines yahan dikhti hain aur full raw output expand karke dekh sakte ho.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),

            if (multi) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: segs.map((seg) {
                    final isSel = seg.index == segIdx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => setState(() => _selectedSeg = seg.index == activeSeg ? null : seg.index),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel ? AppTheme.primary.withOpacity(0.15) : AppTheme.secondary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSel ? AppTheme.primary : AppTheme.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Min ${seg.index + 1}',
                                style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: isSel ? AppTheme.primary : AppTheme.textMuted),
                              ),
                              if (seg.status == 'done') ...[
                                const SizedBox(width: 3),
                                const Text('✓', style: TextStyle(fontSize: 10, color: AppTheme.success)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Is minute ke liye abhi koi chunk result nahi hai.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              )
            else
              ...visible.map((c) => _ChunkRowWidget(
                    scan: widget.scan,
                    chunk: c,
                    segIdx: multi ? segIdx : null,
                    fmtTime: _fmtTime,
                    onRefresh: widget.onRefresh,
                  )),
          ],
        ),
      ),
    );
  }
}

class _ChunkRowWidget extends StatefulWidget {
  final Scan scan;
  final ChunkState chunk;
  final int? segIdx;
  final String Function(double) fmtTime;
  final VoidCallback? onRefresh;

  const _ChunkRowWidget({
    required this.scan,
    required this.chunk,
    this.segIdx,
    required this.fmtTime,
    this.onRefresh,
  });

  @override
  State<_ChunkRowWidget> createState() => _ChunkRowWidgetState();
}

class _ChunkRowWidgetState extends State<_ChunkRowWidget> {
  bool _open = false;
  bool _retrying = false;
  String? _retryError;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      final res = await ScansApi.retryChunk(widget.scan.id, widget.chunk.index, segment: widget.segIdx);
      if (res.statusCode != 200) {
        setState(() => _retryError = 'Retry failed');
      }
      widget.onRefresh?.call();
    } catch (_) {
      setState(() => _retryError = 'Retry failed — network error');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimStart = widget.scan.movieTrimStart ?? 0.0;
    final rangeEnd = widget.scan.movieTrimEnd ?? widget.scan.movieDuration;
    final base = trimStart + widget.chunk.index * CHUNK_SECONDS;
    final end = (base + CHUNK_SECONDS).clamp(0.0, rangeEnd);
    final matches = widget.chunk.matches;
    final raws = widget.chunk.rawOutputs;
    final scanning = widget.chunk.status == 'scanning';
    final isFailed = widget.chunk.status == 'failed' || widget.chunk.status == 'policy_blocked';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${widget.fmtTime(base)} – ${widget.fmtTime(end)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: AppTheme.textForeground),
                ),
                Text(
                  'chunk ${widget.chunk.index}',
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textMuted),
                ),
                if (scanning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('scanning…', style: TextStyle(fontSize: 10, color: AppTheme.primary)),
                  ),
                if (widget.chunk.status == 'no_match' && matches.isEmpty)
                  const Text('no matches in this minute', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                if (widget.chunk.status == 'failed')
                  const Text('failed', style: TextStyle(fontSize: 10, color: AppTheme.destructive)),
                if (widget.chunk.status == 'policy_blocked')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                    ),
                    child: const Text('Flagged by Policy', style: TextStyle(fontSize: 10, color: AppTheme.warning)),
                  ),

                // Matches chips
                ...matches.map((f) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${widget.fmtTime(f.shortStart)}–${widget.fmtTime(f.shortEnd)} → ${widget.fmtTime(f.movieStart)}–${widget.fmtTime(f.movieEnd)}',
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    )),

                // Actions
                OutlinedButton.icon(
                  onPressed: _retrying || scanning ? null : _retry,
                  icon: Icon(_retrying ? Icons.sync : Icons.rotate_left, size: 12),
                  label: Text(_retrying ? 'Retrying…' : isFailed ? 'Retry failed' : 'Retry', style: const TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                if (raws.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(_open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 14),
                    label: Text('AI output (${raws.length})', style: const TextStyle(fontSize: 10)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),

          if (_retryError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: AppTheme.destructive.withOpacity(0.1),
              child: Text(_retryError!, style: const TextStyle(fontSize: 10, color: AppTheme.destructive)),
            ),

          if (_open && raws.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: raws.map((r) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 12, color: AppTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(r.model, style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppTheme.textMuted)),
                              const Spacer(),
                              Text(
                                DateTime.fromMillisecondsSinceEpoch(r.timestamp).toIso8601String().substring(11, 19),
                                style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            r.text,
                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textForeground),
                          ),
                        ],
                      ),
                    )).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
