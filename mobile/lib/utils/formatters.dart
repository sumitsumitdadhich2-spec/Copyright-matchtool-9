import 'package:intl/intl.dart';

class Formatters {
  static String formatDuration(double? seconds) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite) return '00:00.000';
    final totalSec = seconds.abs();
    final hours = (totalSec / 3600).floor();
    final minutes = ((totalSec % 3600) / 60).floor();
    final secs = (totalSec % 60);

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = secs.toStringAsFixed(3).padLeft(6, '0');

    if (hours > 0) {
      final hStr = hours.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  static String formatTimeShort(double? seconds) {
    if (seconds == null || seconds.isNaN || seconds.isInfinite) return '00:00';
    final totalSec = seconds.abs().floor();
    final hours = (totalSec / 3600).floor();
    final minutes = ((totalSec % 3600) / 60).floor();
    final secs = (totalSec % 60);

    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');

    if (hours > 0) {
      final hStr = hours.toString().padLeft(2, '0');
      return '$hStr:$mStr:$sStr';
    }
    return '$mStr:$sStr';
  }

  static String formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  static String formatDate(DateTime dt) {
    return DateFormat('MMM d, y · HH:mm').format(dt);
  }

  /// 1:1 Match of lib/format.ts fmtTime
  static String fmtTime(double sec) {
    final s = sec.clamp(0.0, 360000.0).round();
    final h = (s / 3600).floor();
    final m = ((s % 3600) / 60).floor();
    final ss = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}'
        : '$m:${ss.toString().padLeft(2, '0')}';
  }

  /// 1:1 Match of lib/format.ts fmtBytes
  static String fmtBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 1:1 Match of lib/format.ts fmtDuration
  static String fmtDuration(int ms) {
    final s = (ms / 1000).round();
    final m = (s / 60).floor();
    final ss = s % 60;
    return m > 0 ? '${m}m ${ss}s' : '${ss}s';
  }

  static double? parseTimestamp(String ts) {
    final clean = ts.trim();
    final parts = clean.split(':');
    if (parts.length == 2) {
      final m = double.tryParse(parts[0]);
      final s = double.tryParse(parts[1]);
      if (m != null && s != null) return m * 60 + s;
    } else if (parts.length == 3) {
      final h = double.tryParse(parts[0]);
      final m = double.tryParse(parts[1]);
      final s = double.tryParse(parts[2]);
      if (h != null && m != null && s != null) return h * 3600 + m * 60 + s;
    }
    return null;
  }
}
