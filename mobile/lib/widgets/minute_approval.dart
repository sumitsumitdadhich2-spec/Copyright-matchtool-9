import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 1:1 Port of components/cmt/minute-approval.tsx
/// Pegasus segment_4 approval step: user reviews suggestions and approves movie minutes.

class MinuteSuggestionItem {
  final int minute;
  final int sceneCount;
  final List<String> confidences;

  MinuteSuggestionItem({
    required this.minute,
    required this.sceneCount,
    this.confidences = const [],
  });

  factory MinuteSuggestionItem.fromJson(Map<String, dynamic> json) {
    return MinuteSuggestionItem(
      minute: json['minute'] as int? ?? 0,
      sceneCount: json['sceneCount'] as int? ?? 1,
      confidences: (json['confidences'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class MinuteApproval extends StatefulWidget {
  final String scanId;
  final List<MinuteSuggestionItem> suggestions;
  final VoidCallback onApproved;

  const MinuteApproval({
    super.key,
    required this.scanId,
    required this.suggestions,
    required this.onApproved,
  });

  @override
  State<MinuteApproval> createState() => _MinuteApprovalState();
}

class _MinuteApprovalState extends State<MinuteApproval> {
  late Set<int> _selected;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.suggestions.map((s) => s.minute).toSet();
  }

  void _toggle(int minute) {
    setState(() {
      if (_selected.contains(minute)) {
        _selected.remove(minute);
      } else {
        _selected.add(minute);
      }
    });
  }

  Future<void> _approve() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('/api/scans/${widget.scanId}/merge-pipeline/approve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'minutes': _selected.toList()}),
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        widget.onApproved();
      } else {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() {
          _error = j?['error'] as String? ?? 'Approve failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String? _confSummary(List<String> confidences) {
    if (confidences.isEmpty) return null;
    final counts = <String, int>{};
    for (final c in confidences) {
      final key = c.toLowerCase().trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} x${e.value}' : e.key)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Check karne hain — approve karo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${_selected.length}/${widget.suggestions.length} selected',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pegasus segment_4 matching se ye movie minutes nikle hain. Approve karne ke baad Gemini SIRF in minutes par short-vs-movie compare karega.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),

          // List of suggestions
          ...widget.suggestions.map((s) {
            final isChecked = _selected.contains(s.minute);
            final conf = _confSummary(s.confidences);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => _toggle(s.minute),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border.withOpacity(0.6)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: isChecked,
                          onChanged: (_) => _toggle(s.minute),
                          activeColor: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Minute ${s.minute} ',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${formatSeconds(s.minute * 60)}–${formatSeconds((s.minute + 1) * 60)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textMuted),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '— ${s.sceneCount} scene${s.sceneCount > 1 ? 's' : ''}${conf != null ? ' (confidence: $conf)' : ''}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.destructive)),
          ],

          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: (_submitting || _selected.isEmpty) ? null : _approve,
            icon: _submitting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.check, size: 14),
            label: Text(
              _submitting ? 'Starting...' : 'Approve & Start Gemini Scan',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
