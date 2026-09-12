import 'dart:async';
import 'package:flutter/material.dart';
import '../api/settings_api.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/engine-badge.tsx
/// "16 cores / 16 engines · 3 active" — the ffmpeg engine pool as reported by GET /api/settings.

class EngineBadgeWidget extends StatefulWidget {
  final bool live;

  const EngineBadgeWidget({super.key, this.live = false});

  @override
  State<EngineBadgeWidget> createState() => _EngineBadgeWidgetState();
}

class _EngineBadgeWidgetState extends State<EngineBadgeWidget> {
  Timer? _timer;
  Map<String, dynamic>? _engine;

  @override
  void initState() {
    super.initState();
    _fetchEngine();
    if (widget.live) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchEngine());
    }
  }

  @override
  void didUpdateWidget(covariant EngineBadgeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live != widget.live) {
      _timer?.cancel();
      if (widget.live) {
        _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchEngine());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEngine() async {
    try {
      final res = await SettingsApi.getSettings();
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _engine = res.data['engine'] as Map<String, dynamic>?;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final e = _engine;
    if (e == null) return const SizedBox.shrink();

    final cores = (e['cores'] as num?)?.toInt() ?? 0;
    final engines = (e['engines'] as num?)?.toInt() ?? 0;
    final active = (e['active'] as num?)?.toInt() ?? 0;
    final queued = (e['queued'] as num?)?.toInt() ?? 0;
    final busy = active > 0 || queued > 0;

    return Tooltip(
      message: 'ffmpeg engine pool: $cores CPU cores detected, $engines single-threaded ffmpeg engines${busy ? " — $active running, $queued queued" : ""}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.secondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.memory,
              size: 13,
              color: busy ? AppTheme.primary : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              '$cores cores / $engines engines',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textMuted,
              ),
            ),
            if (busy) ...[
              const SizedBox(width: 4),
              Text(
                '· $active active${queued > 0 ? ", $queued queued" : ""}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
