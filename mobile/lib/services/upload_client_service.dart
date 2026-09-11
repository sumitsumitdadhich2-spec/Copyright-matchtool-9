import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../utils/upload_protocol.dart';

/// 1:1 Port of lib/upload-client.ts
/// Single-stream video upload engine with byte-level auto-resume, speed metering, and connection recovery.

enum UploadPhase {
  probing,
  uploading,
  finalizing,
  reconnecting,
  linking,
}

class UploadProgress {
  final UploadPhase phase;
  final int sent;
  final int total;
  final double? bytesPerSec;
  final double peakBytesPerSec;
  final double? avgBytesPerSec;
  final double? etaSec;
  final int reconnects;
  final int resumedFrom;
  final bool offline;

  UploadProgress({
    required this.phase,
    required this.sent,
    required this.total,
    this.bytesPerSec,
    required this.peakBytesPerSec,
    this.avgBytesPerSec,
    this.etaSec,
    required this.reconnects,
    required this.resumedFrom,
    required this.offline,
  });
}

class UploadResult {
  final double duration;
  final int size;
  final bool reused;

  UploadResult({
    required this.duration,
    required this.size,
    required this.reused,
  });
}

class SpeedMeter {
  final List<Map<String, double>> _samples = [];
  double? rate;
  double peak = 0.0;
  static const double windowMs = 3000.0;

  void sample(int n) {
    final t = DateTime.now().millisecondsSinceEpoch.toDouble();
    _samples.add({'t': t, 'n': n.toDouble()});
    while (_samples.length > 2 && t - _samples[0]['t']! > windowMs) {
      _samples.removeAt(0);
    }
    final first = _samples[0];
    final dt = (t - first['t']!) / 1000.0;
    if (dt < 0.75) return;
    final raw = max(0.0, (n - first['n']!) / dt);
    rate = rate == null ? raw : rate! * 0.7 + raw * 0.3;
    if (rate! > peak) peak = rate!;
  }

  void resetWindow() {
    _samples.clear();
    rate = null;
  }
}

class UploadClientService {
  static String fileFingerprint({required String name, required int size, required int lastModified}) {
    int h = 0;
    final s = '$name|$size|$lastModified';
    for (int i = 0; i < s.length; i++) {
      h = (h * 31 + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return '${h.toRadixString(36)}${size.toRadixString(36)}';
  }

  /// Format speed into human Mbps / Kbps
  static String fmtMbps(double bytesPerSec) {
    final mbps = (bytesPerSec * 8) / 1000000.0;
    if (mbps >= 100) return '${mbps.round()} Mbps';
    if (mbps >= 10) return '${mbps.toStringAsFixed(1)} Mbps';
    if (mbps >= 1) return '${mbps.toStringAsFixed(2)} Mbps';
    return '${(mbps * 1000).round()} Kbps';
  }

  /// Format ETA
  static String fmtEta(double sec) {
    final s = max(1, sec.round());
    if (s < 60) return '${s}s left';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ${(s % 60).toString().padLeft(2, '0')}s left';
    final h = m ~/ 60;
    return '${h}h ${(m % 60).toString().padLeft(2, '0')}m left';
  }
}
