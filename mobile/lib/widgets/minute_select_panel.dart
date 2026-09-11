import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class MinuteSelectPanel extends StatefulWidget {
  final Scan scan;

  const MinuteSelectPanel({super.key, required this.scan});

  @override
  State<MinuteSelectPanel> createState() => _MinuteSelectPanelState();
}

class _MinuteSelectPanelState extends State<MinuteSelectPanel> {
  final Map<int, TextEditingController> _startControllers = {};
  final Map<int, TextEditingController> _endControllers = {};

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(MinuteSelectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scan.shortSegments.length != widget.scan.shortSegments.length) {
      _initControllers();
    }
  }

  void _initControllers() {
    for (final c in _startControllers.values) {
      c.dispose();
    }
    for (final c in _endControllers.values) {
      c.dispose();
    }
    _startControllers.clear();
    _endControllers.clear();

    final trimStart = widget.scan.trimStart;
    final trimEnd = widget.scan.trimEnd ?? widget.scan.movieDuration ?? 3600.0;

    for (final seg in widget.scan.shortSegments) {
      final s = seg.movieRangeStart ?? trimStart;
      final e = seg.movieRangeEnd ?? trimEnd;
      _startControllers[seg.index] = TextEditingController(text: _toHms(s));
      _endControllers[seg.index] = TextEditingController(text: _toHms(e));
    }
  }

  @override
  void dispose() {
    for (final c in _startControllers.values) {
      c.dispose();
    }
    for (final c in _endControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _toHms(double sec) {
    final s = sec.clamp(0, 86400).toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  double? _parseTime(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    final parts = t.split(':');
    try {
      if (parts.length == 1) {
        return double.parse(parts[0]);
      } else if (parts.length == 2) {
        return int.parse(parts[0]) * 60.0 + double.parse(parts[1]);
      } else if (parts.length == 3) {
        return int.parse(parts[0]) * 3600.0 + int.parse(parts[1]) * 60.0 + double.parse(parts[2]);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scanService = context.watch<ScanService>();
    final scan = widget.scan;
    final segs = scan.shortSegments;
    final movieDur = scan.movieDuration ?? 3600.0;
    final trimStart = scan.trimStart;
    final trimEnd = scan.trimEnd ?? movieDur;

    if (segs.isEmpty && scan.chunkCount == 0) return const SizedBox.shrink();

    final selectedCount = segs.where((s) => s.selected != false).length;
    final totalSegs = segs.isNotEmpty ? segs.length : 1;

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
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Short Minutes & Movie Search Selection',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedCount/$totalSegs selected',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Select which minutes of the Short video to scan. For each minute, drag or type the movie search range (From-To) to skip unneeded movie chunks and save Gemini API quota.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),

          // Action Toolbar
          Row(
            children: [
              TextButton.icon(
                onPressed: () => scanService.selectAllShortSegments(),
                icon: const Icon(Icons.select_all, size: 14),
                label: const Text('All', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF38BDF8)),
              ),
              TextButton.icon(
                onPressed: () => scanService.clearAllShortSegments(),
                icon: const Icon(Icons.deselect, size: 14),
                label: const Text('Clear', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.white60),
              ),
              TextButton.icon(
                onPressed: () => scanService.invertShortSegments(),
                icon: const Icon(Icons.swap_horiz, size: 14),
                label: const Text('Invert', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: Colors.white60),
              ),
              const Spacer(),
              if (segs.length > 1)
                ElevatedButton.icon(
                  onPressed: () {
                    final first = segs.first;
                    final s = first.movieRangeStart ?? trimStart;
                    final e = first.movieRangeEnd ?? trimEnd;
                    scanService.setAllShortSegmentsRange(s, e);
                    _initControllers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied range ${_toHms(s)} - ${_toHms(e)} to all minutes')),
                    );
                  },
                  icon: const Icon(Icons.copy_all, size: 13),
                  label: const Text('Same for all', style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Short Minute Segments List
          if (segs.isNotEmpty) ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: segs.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 16),
              itemBuilder: (context, i) {
                final seg = segs[i];
                final isSelected = seg.selected != false;
                final segStart = seg.movieRangeStart ?? trimStart;
                final segEnd = seg.movieRangeEnd ?? trimEnd;

                _startControllers.putIfAbsent(seg.index, () => TextEditingController(text: _toHms(segStart)));
                _endControllers.putIfAbsent(seg.index, () => TextEditingController(text: _toHms(segEnd)));

                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF38BDF8).withOpacity(0.04) : Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF38BDF8).withOpacity(0.3) : Colors.white10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Toggle row
                      Row(
                        children: [
                          Checkbox(
                            value: isSelected,
                            activeColor: const Color(0xFF38BDF8),
                            checkColor: Colors.black,
                            onChanged: (_) => scanService.toggleShortSegment(seg.index),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Minute #${seg.index + 1} (${_toHms(seg.start)} - ${_toHms(seg.end)})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : Colors.white38,
                                  ),
                                ),
                                Text(
                                  'Movie search range: ${_toHms(segStart)} to ${_toHms(segEnd)}',
                                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          if (seg.status == 'done')
                            const Chip(
                              label: Text('Done', style: TextStyle(fontSize: 9, color: Color(0xFF10B981))),
                              backgroundColor: Color(0x1A10B981),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),

                      // Movie Range Slider for this Minute
                      if (isSelected) ...[
                        const SizedBox(height: 4),
                        RangeSlider(
                          values: RangeValues(
                            segStart.clamp(0.0, movieDur - 1.0),
                            segEnd.clamp(segStart + 1.0, movieDur),
                          ),
                          min: 0,
                          max: movieDur > 0 ? movieDur : 100,
                          activeColor: const Color(0xFF38BDF8),
                          inactiveColor: Colors.white12,
                          onChanged: (values) {
                            setState(() {
                              _startControllers[seg.index]?.text = _toHms(values.start);
                              _endControllers[seg.index]?.text = _toHms(values.end);
                            });
                          },
                          onChangeEnd: (values) {
                            scanService.setShortSegmentRange(seg.index, values.start, values.end);
                          },
                        ),
                        // Quick input row
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _startControllers[seg.index],
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  decoration: const InputDecoration(
                                    labelText: 'From',
                                    labelStyle: TextStyle(fontSize: 9),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (v) {
                                    final s = _parseTime(v);
                                    final e = _parseTime(_endControllers[seg.index]?.text ?? '');
                                    if (s != null && e != null && s < e) {
                                      scanService.setShortSegmentRange(seg.index, s, e);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _endControllers[seg.index],
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    labelStyle: TextStyle(fontSize: 9),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (v) {
                                    final s = _parseTime(_startControllers[seg.index]?.text ?? '');
                                    final e = _parseTime(v);
                                    if (s != null && e != null && s < e) {
                                      scanService.setShortSegmentRange(seg.index, s, e);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () {
                                final s = _parseTime(_startControllers[seg.index]?.text ?? '');
                                final e = _parseTime(_endControllers[seg.index]?.text ?? '');
                                if (s != null && e != null && s < e) {
                                  scanService.setShortSegmentRange(seg.index, s, e);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Updated Minute #${seg.index + 1} movie search range.')),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                side: const BorderSide(color: Color(0xFF38BDF8)),
                              ),
                              child: const Text('Save', style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8))),
                            ),
                          ],
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
  }
}
