import 'package:flutter/material.dart';
import '../models/chunk.dart';

class ChunkTimelineWidget extends StatefulWidget {
  final List<ChunkState> chunks;
  final int totalShortMinutes;
  final Function(int chunkIndex)? onChunkTap;
  final Function(int chunkIndex)? onRetryChunk;

  const ChunkTimelineWidget({
    super.key,
    required this.chunks,
    this.totalShortMinutes = 1,
    this.onChunkTap,
    this.onRetryChunk,
  });

  @override
  State<ChunkTimelineWidget> createState() => _ChunkTimelineWidgetState();
}

class _ChunkTimelineWidgetState extends State<ChunkTimelineWidget> {
  int _selectedShortMin = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.chunks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Timeline will populate once movie chunking starts.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      );
    }

    final done = widget.chunks.where((c) => c.status == ChunkStatus.done).length;
    final matchCount = widget.chunks.where((c) => c.matches.isNotEmpty).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.view_timeline_outlined, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Scan Timeline',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (widget.totalShortMinutes > 1) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Min ${_selectedShortMin + 1}/${widget.totalShortMinutes}',
                        style: const TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                '$done/${widget.chunks.length} chunks',
                style: const TextStyle(fontSize: 11, color: Colors.white60, fontFamily: 'monospace'),
              ),
            ],
          ),

          // Short Multi-Minute Tabs (if short video > 60s)
          if (widget.totalShortMinutes > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(widget.totalShortMinutes, (i) {
                  final isSel = i == _selectedShortMin;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('Short Min ${i + 1}', style: const TextStyle(fontSize: 11)),
                      selected: isSel,
                      onSelected: (_) => setState(() => _selectedShortMin = i),
                      selectedColor: const Color(0xFF38BDF8).withOpacity(0.2),
                      checkmarkColor: const Color(0xFF38BDF8),
                    ),
                  );
                }),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Legend
          Row(
            children: [
              _legendItem('Match ($matchCount)', const Color(0xFF22C55E)),
              const SizedBox(width: 10),
              _legendItem('Scanning', const Color(0xFF38BDF8)),
              const SizedBox(width: 10),
              _legendItem('No Match', const Color(0xFF3F3F46)),
              const SizedBox(width: 10),
              _legendItem('Error', const Color(0xFFEF4444)),
            ],
          ),
          const SizedBox(height: 12),

          // Grid of 60s Chunks
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: List.generate(widget.chunks.length, (index) {
              final chunk = widget.chunks[index];
              return _buildChunkTile(context, chunk);
            }),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _buildChunkTile(BuildContext context, ChunkState chunk) {
    Color bg = const Color(0xFF27272A);
    Color border = Colors.transparent;
    Widget? icon;

    switch (chunk.status) {
      case ChunkStatus.pending:
        bg = const Color(0xFF27272A);
        break;
      case ChunkStatus.scanning:
        bg = const Color(0xFF38BDF8).withOpacity(0.2);
        border = const Color(0xFF38BDF8);
        icon = const SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF38BDF8)),
        );
        break;
      case ChunkStatus.done:
        if (chunk.matches.isNotEmpty) {
          bg = const Color(0xFF22C55E);
          icon = const Icon(Icons.check, size: 10, color: Colors.black);
        } else {
          bg = const Color(0xFF3F3F46);
        }
        break;
      case ChunkStatus.error:
        bg = const Color(0xFFEF4444).withOpacity(0.3);
        border = const Color(0xFFEF4444);
        icon = const Icon(Icons.priority_high, size: 10, color: Color(0xFFEF4444));
        break;
    }

    return Tooltip(
      message: 'Minute #${chunk.index + 1} (${chunk.status.name})',
      child: InkWell(
        onTap: () => widget.onChunkTap?.call(chunk.index),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: 1),
          ),
          child: Center(
            child: icon ??
                Text(
                  '${chunk.index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
