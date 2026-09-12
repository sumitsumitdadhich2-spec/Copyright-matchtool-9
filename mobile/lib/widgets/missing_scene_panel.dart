import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 1:1 Port of components/cmt/missing-scene-panel.tsx
/// Targeted Missing Scene Window Scanner: Detect gaps, add custom timestamps, scan 20m windows & verify 24fps.

class MissingSceneTarget {
  final String id;
  final double shortStart;
  final double shortEnd;
  final double duration;

  MissingSceneTarget({
    required this.id,
    required this.shortStart,
    required this.shortEnd,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': shortStart,
    'end': shortEnd,
  };
}

class MissingScenePanel extends StatefulWidget {
  final Scan scan;

  const MissingScenePanel({super.key, required this.scan});

  @override
  State<MissingScenePanel> createState() => _MissingScenePanelState();
}

class _MissingScenePanelState extends State<MissingScenePanel> {
  final List<String> _selectedSceneIds = [];
  final List<MissingSceneTarget> _customScenes = [];
  final TextEditingController _customStartCtrl = TextEditingController();
  final TextEditingController _customEndCtrl = TextEditingController();
  String? _customError;
  bool _actionLoading = false;
  String? _actionError;

  @override
  void dispose() {
    _customStartCtrl.dispose();
    _customEndCtrl.dispose();
    super.dispose();
  }

  double? _parseTime(String val) {
    final trimmed = val.trim();
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(trimmed)) {
      return double.tryParse(trimmed);
    }
    final m = RegExp(r'^(\d+):(\d{1,2}(?:\.\d+)?)$').firstMatch(trimmed);
    if (m != null) {
      final min = int.parse(m.group(1)!);
      final sec = double.parse(m.group(2)!);
      return min * 60.0 + sec;
    }
    return null;
  }

  void _addCustomScene() {
    setState(() => _customError = null);
    final s = _parseTime(_customStartCtrl.text);
    final e = _parseTime(_customEndCtrl.text);
    if (s == null || e == null) {
      setState(() => _customError = 'Valid format enter karein (e.g. 0:30 ya 30.5)');
      return;
    }
    if (e <= s) {
      setState(() => _customError = 'End time start time se bada hona chahiye');
      return;
    }
    final duration = double.parse((e - s).toStringAsFixed(3));
    final id = 'custom-${DateTime.now().millisecondsSinceEpoch}-${s.round()}-${e.round()}';
    final target = MissingSceneTarget(
      id: id,
      shortStart: s,
      shortEnd: e,
      duration: duration,
    );

    setState(() {
      _customScenes.add(target);
      _selectedSceneIds.add(id);
      _customStartCtrl.clear();
      _customEndCtrl.clear();
    });
  }

  void _removeCustomScene(String id) {
    setState(() {
      _customScenes.removeWhere((s) => s.id == id);
      _selectedSceneIds.remove(id);
    });
  }

  void _toggleScene(String id) {
    setState(() {
      if (_selectedSceneIds.contains(id)) {
        _selectedSceneIds.remove(id);
      } else {
        _selectedSceneIds.add(id);
      }
    });
  }

  Future<void> _startScan(List<MissingSceneTarget> scenes) async {
    if (scenes.isEmpty) {
      setState(() => _actionError = 'Kripya search karne ke liye kam se kam 1 scene select karein.');
      return;
    }
    setState(() {
      _actionLoading = true;
      _actionError = null;
    });

    try {
      final res = await http.post(
        Uri.parse('/api/scans/${widget.scan.id}/missing-scene-scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'scenes': scenes.map((s) => s.toJson()).toList(),
        }),
      );
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() => _actionError = j?['error'] as String? ?? 'Failed to start missing scene scan');
      }
    } catch (err) {
      if (mounted) setState(() => _actionError = err.toString());
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _stopScan() async {
    setState(() => _actionLoading = true);
    try {
      await http.delete(Uri.parse('/api/scans/${widget.scan.id}/missing-scene-scan'));
    } catch (err) {
      if (mounted) setState(() => _actionError = err.toString());
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Collect detected gaps from scan
    final detectedGaps = widget.scan.unmappedGaps.asMap().entries.map((entry) {
      final idx = entry.key;
      final g = entry.value;
      return MissingSceneTarget(
        id: 'gap-$idx-${g.start.round()}-${g.end.round()}',
        shortStart: g.start,
        shortEnd: g.end,
        duration: double.parse((g.end - g.start).toStringAsFixed(3)),
      );
    }).toList();

    final allAvailableScenes = [...detectedGaps, ..._customScenes];
    final selectedScenes = allAvailableScenes.where((s) => _selectedSceneIds.contains(s.id)).toList();

    final state = widget.scan.missingSceneScan;
    final isRunning = state != null && ['preparing', 'scanning_windows', 'scanning_chunks', 'verifying'].contains(state['status']);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search, size: 16, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Targeted Missing Scene Window Scanner',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Jo scene short me nahi mile, unhe 20-min movie windows me dhoondein aur 24 fps par verify karein',
                      style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              if (isRunning)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      SizedBox(width: 4),
                      Text('Scanning in progress', style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else if (state?['status'] == 'done')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                      SizedBox(width: 4),
                      Text('Done', style: TextStyle(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          // Detected scenes list
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Missing Scene(s) to search (${selectedScenes.length} selected):',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              if (allAvailableScenes.isNotEmpty)
                Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _selectedSceneIds..clear()..addAll(allAvailableScenes.map((s) => s.id))),
                      child: Text('Select All (${allAvailableScenes.length})', style: const TextStyle(fontSize: 11, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 6),
                    const Text('·', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() => _selectedSceneIds.clear()),
                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 8),
          if (allAvailableScenes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border, style: BorderStyle.solid),
              ),
              child: const Text(
                'Filhal koi missing gap detect nahi hua ya scan abhi poora nahi hua. Neeche se custom time range add karein.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allAvailableScenes.asMap().entries.map((entry) {
                final idx = entry.key;
                final scene = entry.value;
                final isSelected = _selectedSceneIds.contains(scene.id);
                final isCustom = scene.id.startsWith('custom-');

                return InkWell(
                  onTap: () => _toggleScene(scene.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withOpacity(0.1) : AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleScene(scene.id),
                            activeColor: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatSeconds(scene.shortStart)} – ${formatSeconds(scene.shortEnd)}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Duration: ${scene.duration.toStringAsFixed(1)}s${isCustom ? ' (Custom)' : ' · Gap #${idx + 1}'}',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 14, color: AppTheme.destructive),
                            onPressed: () => _removeCustomScene(scene.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

          const SizedBox(height: 10),
          // Custom Range Adder
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.background.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border.withOpacity(0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Or Add Custom Missing Scene Timestamp:', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      height: 32,
                      child: TextField(
                        controller: _customStartCtrl,
                        style: const TextStyle(fontSize: 11),
                        decoration: const InputDecoration(
                          hintText: 'Start (e.g. 0:30)',
                          hintStyle: TextStyle(fontSize: 10),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('to', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ),
                    SizedBox(
                      width: 100,
                      height: 32,
                      child: TextField(
                        controller: _customEndCtrl,
                        style: const TextStyle(fontSize: 11),
                        decoration: const InputDecoration(
                          hintText: 'End (e.g. 0:40)',
                          hintStyle: TextStyle(fontSize: 10),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _addCustomScene,
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Add Scene', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    ),
                  ],
                ),
                if (_customError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_customError!, style: const TextStyle(fontSize: 10, color: AppTheme.destructive)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          // Actions
          Row(
            children: [
              if (!isRunning)
                ElevatedButton.icon(
                  onPressed: _actionLoading || selectedScenes.isEmpty ? null : () => _startScan(selectedScenes),
                  icon: _actionLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.play_arrow, size: 14),
                  label: Text(
                    _actionLoading
                        ? 'Starting...'
                        : selectedScenes.length <= 1
                            ? 'Scan Windows for 1 Selected Scene'
                            : 'Merge ${selectedScenes.length} Scenes & Scan Windows',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _actionLoading ? null : _stopScan,
                  icon: const Icon(Icons.stop, size: 14),
                  label: const Text('Stop Scanner', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive),
                ),
            ],
          ),

          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_actionError!, style: const TextStyle(fontSize: 11, color: AppTheme.destructive)),
            ),

          // Active Status, Window Hits, and Verified Matches
          if (state != null && state['status'] != 'idle') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Scanner Status:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      Text(
                        (state['status'] as String? ?? '').replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (state['progress'] != null) ...[
                    const SizedBox(height: 4),
                    Text(state['progress'] as String, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
