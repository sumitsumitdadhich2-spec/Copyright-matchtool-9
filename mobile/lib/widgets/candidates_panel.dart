import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class CandidatesPanel extends StatelessWidget {
  final Scan scan;
  final Function(ChunkMatch match)? onSelectMatch;

  const CandidatesPanel({super.key, required this.scan, this.onSelectMatch});

  @override
  Widget build(BuildContext context) {
    final matches = scan.matches;
    final scanService = context.read<ScanService>();

    if (matches.isEmpty) {
      return const SizedBox.shrink();
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
              Row(
                children: [
                  const Icon(Icons.saved_search, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'AI Candidate Matches (${matches.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Text(
                '${scan.verifiedMatchesCount} Verified',
                style: const TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: matches.length,
            separatorBuilder: (_, __) => const Divider(height: 12, color: Colors.white10),
            itemBuilder: (context, index) {
              final m = matches[index];
              return InkWell(
                onTap: () => onSelectMatch?.call(m),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (m.verified == true ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: m.verified == true ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Short: ${Formatters.formatDuration(m.shortStart)} - ${Formatters.formatDuration(m.shortEnd)}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '(${m.duration.toStringAsFixed(1)}s)',
                                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                                ),
                              ],
                            ),
                            Text(
                              'Movie Match: ${Formatters.formatDuration(m.movieStart)} - ${Formatters.formatDuration(m.movieEnd)}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
                            ),
                            if (m.reason != null && m.reason!.isNotEmpty)
                              Text(
                                m.reason!,
                                style: const TextStyle(fontSize: 10, color: Colors.white54, fontStyle: FontStyle.italic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          m.verified == true ? Icons.verified : Icons.shield_outlined,
                          size: 18,
                          color: m.verified == true ? const Color(0xFF34D399) : Colors.white38,
                        ),
                        tooltip: 'Verify candidate (24fps AI)',
                        onPressed: () => scanService.verifyMatch(m),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
