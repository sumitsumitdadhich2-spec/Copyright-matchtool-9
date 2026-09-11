import 'package:flutter/material.dart';
import '../models/chunk.dart';

class ChunkTimelineWidget extends StatelessWidget {
  final List<ChunkState> chunks;
  final Function(int chunkIndex)? onChunkTap;
  final Function(int chunkIndex)? onRetryChunk;

  const ChunkTimelineWidget({
    super.key,
    required this.chunks,
    this.onChunkTap,
    this.onRetryChunk,
  });

  @override
  Widget build(BuildContext context) {
    if (chunks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Timeline will populate once movie chunking starts.',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Chunk Timeline',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Row(
                children: [
                  _legendItem('Match', const Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  _legendItem('Scanning', const Color(0xFF6366F1)),
                  const SizedBox(width: 8),
                  _legendItem('No Match', const Color(0xFF333333)),
                  const SizedBox(width: 8),
                  _legendItem('Failed', const Color(0xFFEF4444)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(chunks.length, (index) {
              final chunk = chunks[index];
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
    Color bg;
    Color border;
    Widget? icon;

    switch (chunk.status) {
      case ChunkStatus.match:
        bg = const Color(0xFF22C55E).withOpacity(0.25);
        border = const Color(0xFF22C55E);
        icon = const Icon(Icons.check, size: 10, color: Color(0xFF22C55E));
        break;
      case ChunkStatus.scanning:
        bg = const Color(0xFF6366F1).withOpacity(0.3);
        border = const Color(0xFF6366F1);
        icon = const SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
        );
        break;
      case ChunkStatus.failed:
        bg = const Color(0xFFEF4444).withOpacity(0.25);
        border = const Color(0xFFEF4444);
        icon = const Icon(Icons.refresh, size: 10, color: Color(0xFFEF4444));
        break;
      case ChunkStatus.noMatch:
        bg = const Color(0xFF262626);
        border = const Color(0xFF383838);
        break;
      case ChunkStatus.pending:
      default:
        bg = const Color(0xFF1A1A1A);
        border = const Color(0xFF2A2A2A);
    }

    final chunkMinute = chunk.index;

    return InkWell(
      onTap: () {
        if (chunk.status == ChunkStatus.failed && onRetryChunk != null) {
          onRetryChunk!(chunk.index);
        } else if (onChunkTap != null) {
          onChunkTap!(chunk.index);
        } else {
          _showChunkDetailsDialog(context, chunk);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Tooltip(
        message: 'Chunk #${chunk.index + 1} (${chunkMinute}m-${chunkMinute + 1}m): ${chunk.status.name}',
        child: Container(
          width: 38,
          height: 32,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border, width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${chunk.index + 1}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (icon != null) icon,
            ],
          ),
        ),
      ),
    );
  }

  void _showChunkDetailsDialog(BuildContext context, ChunkState chunk) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Chunk #${chunk.index + 1} (${chunk.index}m - ${chunk.index + 1}m)'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Status: ${chunk.status.name.toUpperCase()}'),
              const SizedBox(height: 6),
              Text('Attempts: ${chunk.attempts}'),
              const SizedBox(height: 6),
              Text('Matches Found: ${chunk.matches.length}'),
              if (chunk.error != null) ...[
                const SizedBox(height: 12),
                const Text('Error:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                Text(chunk.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              if (chunk.rawOutput != null && chunk.rawOutput!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Gemini Raw Output:', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chunk.rawOutput!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (chunk.status == ChunkStatus.failed && onRetryChunk != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                onRetryChunk!(chunk.index);
              },
              child: const Text('Retry Chunk'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
