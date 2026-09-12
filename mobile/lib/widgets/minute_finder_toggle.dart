import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/minute-finder-toggle.tsx
/// Segmented control: which minute finder runs after upload + trim confirm.
/// Persists via PUT /api/settings.

enum MinuteFinderMode { gemini, twelvelabs, off }

class MinuteFinderToggle extends StatefulWidget {
  final String mode;
  final ValueChanged<String>? onChanged;

  const MinuteFinderToggle({
    super.key,
    required this.mode,
    this.onChanged,
  });

  @override
  State<MinuteFinderToggle> createState() => _MinuteFinderToggleState();
}

class _MinuteFinderToggleState extends State<MinuteFinderToggle> {
  String? _saving;
  String? _error;

  static const List<Map<String, String>> _options = [
    {
      'value': 'gemini',
      'label': 'Gemini',
      'title': 'Gemini Minute Finder — 20-min windows @ 10fps/1fps, phir auto chunk scan',
    },
    {
      'value': 'twelvelabs',
      'label': 'TwelveLabs',
      'title': 'Purana flow — merge → Marengo → Pegasus → minute approval',
    },
    {
      'value': 'off',
      'label': 'Off',
      'title': 'Koi minute finder nahi — manual Start = normal Full scan',
    },
  ];

  Future<void> _pick(String next) async {
    if (next == widget.mode || _saving != null) return;
    setState(() {
      _saving = next;
      _error = null;
    });

    try {
      final res = await http.put(
        Uri.parse('/api/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'minuteFinder': next}),
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        widget.onChanged?.(next);
      } else {
        final j = jsonDecode(res.body) as Map<String, dynamic>?;
        setState(() {
          _error = j?['error'] as String? ?? 'Save failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'Minute finder:',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ),
              ..._options.map((o) {
                final val = o['value']!;
                final active = val == widget.mode;
                final busy = _saving == val;

                return Tooltip(
                  message: o['title']!,
                  child: InkWell(
                    onTap: _saving != null ? null : () => _pick(val),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? AppTheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy) ...[
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            o['label']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: active ? Colors.black : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(_error!, style: const TextStyle(fontSize: 10, color: AppTheme.destructive)),
          ),
      ],
    );
  }
}
