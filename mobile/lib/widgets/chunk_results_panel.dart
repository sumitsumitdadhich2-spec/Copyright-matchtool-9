import 'package:flutter/material.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../utils/formatters.dart';

class ChunkResultsPanel extends StatefulWidget {
  final Scan scan;

  const ChunkResultsPanel({super.key, required this.scan});

  @override
  State<ChunkResultsPanel> createState() => _ChunkResultsPanelState();
}

class _ChunkResultsPanelState extends State<ChunkResultsPanel> {
  int? _expandedChunkIndex;

  @override
  Widget build(BuildContext context) {
    final chunks = widget.scan.chunks.where((c) => c.status != ChunkStatus.pending).toList();

    if (chunks.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_empty, color: Colors.white38, size: 18),
            SizedBox(width: 8),
            Text(
              'No chunk outputs yet. Start scan to see raw minute-by-minute results.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      );
    }

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.list_alt, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Chunk Timeline — Matches Per Minute',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${chunks.length}/${widget.scan.chunkCount} Chunks',
                  style: const TextStyle(fontSize: 9, color: Colors.white70, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Har movie minute ke liye AI raw match breakdown aur extracted scene logs.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: chunks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final chunk = chunks[index];
              final isExpanded = _expandedChunkIndex == chunk.index;
              final isDone = chunk.status == ChunkStatus.done;
              final hasMatch = chunk.matches.isNotEmpty;

              return Container(
                decoration: BoxDecoration(
                  color: hasMatch
                      ? const Color(0xFF10B981).withOpacity(0.08)
                      : (isDone ? Colors.black26 : const Color(0xFF38BDF8).withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasMatch
                        ? const Color(0xFF10B981).withOpacity(0.3)
                        : (isDone ? Colors.white10 : const Color(0xFF38BDF8).withOpacity(0.2)),
                  ),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _expandedChunkIndex = isExpanded ? null : chunk.index;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              hasMatch ? Icons.check_circle : (isDone ? Icons.remove_circle_outline : Icons.sync),
                              color: hasMatch
                                  ? const Color(0xFF10B981)
                                  : (isDone ? Colors.white38 : const Color(0xFF38BDF8)),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Minute #${chunk.index + 1} (${Formatters.formatDuration(chunk.startTime)} - ${Formatters.formatDuration(chunk.endTime)})',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    hasMatch
                                        ? '${chunk.matches.length} scene match found in this chunk'
                                        : (isDone ? 'No match in this minute' : 'Scanning chunk...'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: hasMatch ? const Color(0xFF34D399) : Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isExpanded ? Icons.expand_less : Icons.expand_more,
                              color: Colors.white60,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded) ...[
                      const Divider(height: 1, color: Colors.white10),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (chunk.matches.isNotEmpty) ...[
                              const Text(
                                'EXTRACTED MATCHES:',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                              ),
                              const SizedBox(height: 4),
                              ...chunk.matches.map((m) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.arrow_right, color: Color(0xFF10B981), size: 14),
                                        Expanded(
                                          child: Text(
                                            'Short [${Formatters.formatDuration(m.shortStart)}-${Formatters.formatDuration(m.shortEnd)}] ➔ Movie [${Formatters.formatDuration(m.movieStart)}-${Formatters.formatDuration(m.movieEnd)}] (Confidence: ${(m.confidence * 100).toInt()}%)',
                                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                            if (chunk.rawOutput != null && chunk.rawOutput!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              const Text(
                                'AI RAW FORENSIC OUTPUT:',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white60),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  chunk.rawOutput!,
                                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70),
                                ),
                              ),
                            ],
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
      ),
    );
  }
}
