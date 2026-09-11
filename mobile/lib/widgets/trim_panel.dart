import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class TrimPanel extends StatefulWidget {
  final Scan scan;

  const TrimPanel({super.key, required this.scan});

  @override
  State<TrimPanel> createState() => _TrimPanelState();
}

class _TrimPanelState extends State<TrimPanel> {
  late double _start;
  late double _end;
  late TextEditingController _startController;
  late TextEditingController _endController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final movieDur = widget.scan.movieDuration ?? 3600.0;
    _start = widget.scan.trimStart.clamp(0.0, movieDur);
    _end = (widget.scan.trimEnd ?? movieDur).clamp(_start + 1.0, movieDur);
    _startController = TextEditingController(text: _toHms(_start));
    _endController = TextEditingController(text: _toHms(_end));
  }

  @override
  void didUpdateWidget(TrimPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scan.trimStart != widget.scan.trimStart ||
        oldWidget.scan.trimEnd != widget.scan.trimEnd) {
      final movieDur = widget.scan.movieDuration ?? 3600.0;
      _start = widget.scan.trimStart.clamp(0.0, movieDur);
      _end = (widget.scan.trimEnd ?? movieDur).clamp(_start + 1.0, movieDur);
      _startController.text = _toHms(_start);
      _endController.text = _toHms(_end);
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
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

  void _applyManualInputs(double movieDur, ScanService scanService) {
    final s = _parseTime(_startController.text);
    final e = _parseTime(_endController.text);

    if (s == null || e == null) {
      setState(() => _error = 'Invalid time format. Use HH:MM:SS or MM:SS');
      return;
    }
    if (s >= e) {
      setState(() => _error = 'End time must be greater than start time');
      return;
    }
    if (s < 0 || e > movieDur) {
      setState(() => _error = 'Range must be within 00:00 - ${_toHms(movieDur)}');
      return;
    }

    setState(() {
      _start = s;
      _end = e;
      _error = null;
    });
    scanService.setTrim(s, e);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Movie Trim updated: ${_toHms(s)} - ${_toHms(e)} (${_toHms(e - s)})')),
    );
  }

  void _applyPreset(double start, double end, double movieDur, ScanService scanService) {
    final s = start.clamp(0.0, movieDur);
    final e = end.clamp(s + 1.0, movieDur);
    setState(() {
      _start = s;
      _end = e;
      _startController.text = _toHms(s);
      _endController.text = _toHms(e);
      _error = null;
    });
    scanService.setTrim(s, e);
  }

  @override
  Widget build(BuildContext context) {
    final movieDur = widget.scan.movieDuration ?? 3600.0;
    final scanService = context.read<ScanService>();
    final trimmedDuration = (_end - _start).clamp(0.0, movieDur);
    final totalChunks = (trimmedDuration / 60.0).ceil();

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
                  Icon(Icons.content_cut, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Movie Range Trimmer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalChunks chunks (${_toHms(trimmedDuration)})',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Exclude intro, credits or unrelated movie scenes to save AI quota and accelerate scan speed.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 12),

          // Quick Presets Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip('Full Movie', () => _applyPreset(0, movieDur, movieDur, scanService)),
                const SizedBox(width: 6),
                _buildPresetChip('First 15m', () => _applyPreset(0, 15 * 60.0, movieDur, scanService)),
                const SizedBox(width: 6),
                _buildPresetChip('First 30m', () => _applyPreset(0, 30 * 60.0, movieDur, scanService)),
                const SizedBox(width: 6),
                _buildPresetChip('First 60m', () => _applyPreset(0, 60 * 60.0, movieDur, scanService)),
                const SizedBox(width: 6),
                _buildPresetChip('Middle 30m', () {
                  final mid = movieDur / 2;
                  _applyPreset(mid - 15 * 60, mid + 15 * 60, movieDur, scanService);
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Range Slider
          RangeSlider(
            values: RangeValues(_start.clamp(0.0, movieDur - 1.0), _end.clamp(_start + 1.0, movieDur)),
            min: 0,
            max: movieDur > 0 ? movieDur : 100,
            activeColor: const Color(0xFFF59E0B),
            inactiveColor: Colors.white12,
            onChanged: (values) {
              setState(() {
                _start = values.start;
                _end = values.end;
                _startController.text = _toHms(values.start);
                _endController.text = _toHms(values.end);
                _error = null;
              });
            },
            onChangeEnd: (values) {
              scanService.setTrim(values.start, values.end);
            },
          ),

          // Start & End Text Field Inputs
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'From (HH:MM:SS)',
                    labelStyle: TextStyle(fontSize: 10, color: Colors.white60),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyManualInputs(movieDur, scanService),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _endController,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'To (HH:MM:SS)',
                    labelStyle: TextStyle(fontSize: 10, color: Colors.white60),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _applyManualInputs(movieDur, scanService),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _applyManualInputs(movieDur, scanService),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: const Text('Set', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
          ],
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      backgroundColor: Colors.white.withOpacity(0.05),
      side: const BorderSide(color: Colors.white12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }
}
