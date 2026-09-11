import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class RenderPanel extends StatefulWidget {
  final Scan scan;

  const RenderPanel({super.key, required this.scan});

  @override
  State<RenderPanel> createState() => _RenderPanelState();
}

class _RenderPanelState extends State<RenderPanel> {
  int _selectedMatchIndex = 0;
  bool _rendering = false;

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    final renderJob = widget.scan.renderJob;
    final scanService = context.read<ScanService>();

    if (matches.isEmpty) {
      return const SizedBox.shrink();
    }

    final match = matches[_selectedMatchIndex.clamp(0, matches.length - 1)];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.video_library, color: Color(0xFF818CF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Local FFmpeg Render Studio',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF818CF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ON-DEVICE',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFA5B4FC)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Stitches together the Short clip and Movie segment into a dual-view split screen video proof file right on your device.',
            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.65)),
          ),
          const SizedBox(height: 12),

          // Dropdown to select which match to render
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedMatchIndex.clamp(0, matches.length - 1),
                isExpanded: true,
                dropdownColor: const Color(0xFF27272A),
                items: List.generate(matches.length, (i) {
                  final m = matches[i];
                  return DropdownMenuItem(
                    value: i,
                    child: Text(
                      'Match #${i + 1}: ${Formatters.formatDuration(m.shortStart)} ➔ ${Formatters.formatDuration(m.movieStart)} (${m.duration.toStringAsFixed(1)}s)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMatchIndex = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Progress indicator during render
          if (_rendering || renderJob.status == 'rendering') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: renderJob.progress > 0 ? renderJob.progress / 100.0 : null,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF818CF8)),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Rendering with local FFmpeg: ${renderJob.progress.toInt()}%',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA5B4FC)),
            ),
            const SizedBox(height: 10),
          ],

          // Render Success Path
          if (renderJob.status == 'done' && renderJob.outputPath != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Output: ${renderJob.outputPath}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF34D399)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _rendering
                  ? null
                  : () async {
                      setState(() => _rendering = true);
                      final path = await scanService.renderMatchSideBySide(match);
                      if (mounted) {
                        setState(() => _rendering = false);
                        if (path != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Rendered proof video created:\n$path')),
                          );
                        }
                      }
                    },
              icon: _rendering
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.movie_creation_outlined, size: 18),
              label: Text(
                _rendering ? 'Rendering on CPU...' : 'Render Side-by-Side Proof MP4',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF818CF8),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
