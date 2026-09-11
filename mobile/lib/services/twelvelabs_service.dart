import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/scan.dart';
import '../utils/segment_range.dart';
import 'media_service.dart';
import 'json_record_service.dart';

/// 1:1 Port of lib/twelvelabs.ts
/// TwelveLabs Marengo 3.0 Pre-filter Service with embedding extraction, cosine similarity, and chunk filtering.

const String TL_BASE = 'https://api.twelvelabs.io/v1.3';
const String INDEX_NAME = 'cmt-prefilter';
const double TL_SIMILARITY_THRESHOLD = 0.82;

class TLSegment {
  final double start;
  final double end;
  final String option;
  final List<double> embedding;

  const TLSegment({
    required this.start,
    required this.end,
    required this.option,
    required this.embedding,
  });

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'option': option,
        'embedding': embedding,
      };

  factory TLSegment.fromJson(Map<String, dynamic> json) => TLSegment(
        start: (json['start'] as num?)?.toDouble() ?? 0.0,
        end: (json['end'] as num?)?.toDouble() ?? 0.0,
        option: json['option'] ?? 'visual',
        embedding: (json['embedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      );
}

class StoredEmbeddings {
  final String indexId;
  final String videoId;
  final int savedAt;
  final List<TLSegment> segments;

  StoredEmbeddings({
    required this.indexId,
    required this.videoId,
    required this.savedAt,
    required this.segments,
  });

  Map<String, dynamic> toJson() => {
        'indexId': indexId,
        'videoId': videoId,
        'savedAt': savedAt,
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory StoredEmbeddings.fromJson(Map<String, dynamic> json) => StoredEmbeddings(
        indexId: json['indexId'] ?? '',
        videoId: json['videoId'] ?? '',
        savedAt: json['savedAt'] ?? 0,
        segments: (json['segments'] as List<dynamic>?)?.map((s) => TLSegment.fromJson(s as Map<String, dynamic>)).toList() ?? [],
      );
}

class PrefilterComputation {
  final Map<int, Set<int>>? perSegment;
  final Map<int, Map<int, double>>? confidence;
  final Map<int, List<Map<String, double>>>? expectedWindows;
  final String? reason;

  PrefilterComputation({
    this.perSegment,
    this.confidence,
    this.expectedWindows,
    this.reason,
  });
}

class TwelveLabsService {
  static Future<dynamic> _tlFetch(String apiKey, String pathname, {String method = 'GET', dynamic body, Map<String, String>? headers}) async {
    final uri = Uri.parse('$TL_BASE$pathname');
    http.Response resp;
    final reqHeaders = {
      'x-api-key': apiKey,
      if (headers != null) ...headers,
    };

    if (method == 'POST') {
      reqHeaders['Content-Type'] = 'application/json';
      resp = await http.post(uri, headers: reqHeaders, body: body != null ? jsonEncode(body) : null);
    } else {
      resp = await http.get(uri, headers: reqHeaders);
    }

    dynamic json;
    try {
      json = jsonDecode(resp.body);
    } catch (_) {}

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      final msg = json != null && json['message'] != null ? json['message'].toString() : resp.body;
      throw Exception('Twelve Labs $method $pathname failed (${resp.statusCode}): $msg');
    }
    return json;
  }

  /// Find or create Marengo-only index
  static Future<String> ensureIndex(String apiKey) async {
    try {
      final listed = await _tlFetch(apiKey, '/indexes?index_name=${Uri.encodeComponent(INDEX_NAME)}&page_limit=1');
      if (listed['data'] != null && (listed['data'] as List).isNotEmpty) {
        final found = listed['data'][0];
        final id = found['_id'] ?? found['id'];
        if (id != null) return id.toString();
      }
    } catch (_) {}

    final created = await _tlFetch(apiKey, '/indexes', method: 'POST', body: {
      'index_name': INDEX_NAME,
      'models': [
        {'model_name': 'marengo3.0', 'model_options': ['visual', 'audio']}
      ],
    });
    final id = created['_id'] ?? created['id'];
    if (id == null) throw Exception('Index create returned no id');
    return id.toString();
  }

  /// Upload video file as indexing task
  static Future<Map<String, String?>> createIndexTask(String apiKey, String indexId, String filePath) async {
    final uri = Uri.parse('$TL_BASE/tasks');
    final request = http.MultipartRequest('POST', uri);
    request.headers['x-api-key'] = apiKey;
    request.fields['index_id'] = indexId;
    request.files.add(await http.MultipartFile.fromPath('video_file', filePath, filename: p.basename(filePath)));

    final streamedResp = await request.send();
    final resp = await http.Response.fromStream(streamedResp);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Task create failed (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    final taskId = data['_id'] ?? data['id'];
    final videoId = data['video_id'];
    return {'taskId': taskId?.toString(), 'videoId': videoId?.toString()};
  }

  /// Poll indexing task until ready
  static Future<String> pollTaskUntilReady(
    String apiKey,
    String taskId, {
    int intervalMs = 10000,
    int timeoutMs = 4 * 60 * 60 * 1000,
    void Function(String)? onTick,
  }) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      final resp = await _tlFetch(apiKey, '/tasks/$taskId');
      final status = resp['status'] ?? 'unknown';
      final videoId = resp['video_id']?.toString();
      onTick?.call(status);

      if (status == 'ready') {
        if (videoId == null) throw Exception('Task ready but no video_id');
        return videoId;
      }
      if (status == 'failed' || status == 'error') {
        throw Exception('Indexing task $taskId failed (status: $status)');
      }
      if (DateTime.now().millisecondsSinceEpoch - startedAt > timeoutMs) {
        throw Exception('Indexing task $taskId timed out');
      }
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
  }

  /// Cosine Similarity calculation
  static double cosineSimilarity(List<double> a, List<double> b) {
    final n = min(a.length, b.length);
    if (n == 0) return 0.0;
    double dot = 0.0;
    double na = 0.0;
    double nb = 0.0;
    for (int i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = sqrt(na) * sqrt(nb);
    return denom == 0.0 ? 0.0 : dot / denom;
  }

  /// Compute prefilter chunks
  static PrefilterComputation computePrefilterChunks({
    required Scan scan,
    required List<ShortSegmentState> shortSegments,
    required List<TLSegment> shortEmb,
    required List<TLSegment> movieEmb,
  }) {
    if (shortEmb.isEmpty || movieEmb.isEmpty) {
      return PrefilterComputation(perSegment: null, reason: 'no embeddings available');
    }

    final trimStart = scan.movieTrimStart ?? 0.0;
    final chunkCount = scan.chunks.length;

    final movieByOption = <String, List<TLSegment>>{};
    for (final m in movieEmb) {
      movieByOption.putIfAbsent(m.option, () => []).add(m);
    }

    final matchesByShortSeg = <TLSegment, Map<String, dynamic>>{};

    for (final s in shortEmb) {
      final candidates = movieByOption[s.option] ?? [];
      double bestSim = -1.0;
      final hits = <Map<String, double>>[];
      for (final m in candidates) {
        final sim = cosineSimilarity(s.embedding, m.embedding);
        if (sim > bestSim) bestSim = sim;
        if (sim >= TL_SIMILARITY_THRESHOLD) {
          hits.add({'t': m.start, 'sim': sim});
          hits.add({'t': m.end, 'sim': sim});
        }
      }
      matchesByShortSeg[s] = {'bestSim': bestSim, 'hits': hits};
    }

    final byWindow = <String, Map<String, dynamic>>{};
    for (final entry in matchesByShortSeg.entries) {
      final seg = entry.key;
      final res = entry.value;
      final key = '${seg.start.toStringAsFixed(1)}-${seg.end.toStringAsFixed(1)}';
      final w = byWindow.putIfAbsent(key, () => {
            'start': seg.start,
            'end': seg.end,
            'matched': false,
            'hits': <Map<String, double>>[],
          });
      final hitsList = res['hits'] as List<Map<String, double>>;
      if (hitsList.isNotEmpty) w['matched'] = true;
      (w['hits'] as List<Map<String, double>>).addAll(hitsList);
    }

    for (final w in byWindow.values) {
      if (w['matched'] != true) {
        return PrefilterComputation(
          perSegment: null,
          reason: 'short ${(w['start'] as double).toStringAsFixed(0)}s–${(w['end'] as double).toStringAsFixed(0)}s had no $TL_SIMILARITY_THRESHOLD+ match anywhere — full scan for safety',
        );
      }
    }

    int timeToChunk(double t) => ((t - trimStart) / CHUNK_SECONDS).floor();

    final perSegment = <int, Set<int>>{};
    final confidence = <int, Map<int, double>>{};
    final expectedWindows = <int, List<Map<String, double>>>{};

    for (final shortMin in shortSegments) {
      final set = <int>{};
      final conf = <int, double>{};
      final windows = <Map<String, double>>[];

      for (final w in byWindow.values) {
        final wStart = w['start'] as double;
        final wEnd = w['end'] as double;
        if (wStart >= shortMin.end || wEnd <= shortMin.start) continue;

        windows.add({'start': max(wStart, shortMin.start), 'end': min(wEnd, shortMin.end)});
        final hits = w['hits'] as List<Map<String, double>>;
        for (final h in hits) {
          final ci = timeToChunk(h['t']!);
          for (final c in [ci - 1, ci, ci + 1]) {
            if (c >= 0 && c < chunkCount) {
              set.add(c);
              final sim = c == ci ? h['sim']! : h['sim']! - 0.03;
              if ((conf[c] ?? -1.0) < sim) conf[c] = sim;
            }
          }
        }
      }

      perSegment[shortMin.index] = set;
      confidence[shortMin.index] = conf;
      expectedWindows[shortMin.index] = windows;
    }

    return PrefilterComputation(
      perSegment: perSegment,
      confidence: confidence,
      expectedWindows: expectedWindows,
    );
  }
}
