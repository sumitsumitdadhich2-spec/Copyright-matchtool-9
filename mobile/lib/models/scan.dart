import 'chunk.dart';

enum ScanStatus {
  created,
  uploading,
  chunking,
  ready,
  scanning,
  verifying,
  done,
  stopped,
  error,
}

class Scan {
  final String id;
  final DateTime createdAt;
  ScanStatus status;
  String? shortPath;
  String? moviePath;
  String? shortName;
  String? movieName;
  int? shortSize;
  int? movieSize;
  double? shortDuration;
  double? movieDuration;
  int chunkCount;
  double chunkingProgress;
  List<ChunkState> chunks;
  List<ChunkMatch> matches;
  String? error;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? selectedModel;

  Scan({
    required this.id,
    required this.createdAt,
    this.status = ScanStatus.created,
    this.shortPath,
    this.moviePath,
    this.shortName,
    this.movieName,
    this.shortSize,
    this.movieSize,
    this.shortDuration,
    this.movieDuration,
    this.chunkCount = 0,
    this.chunkingProgress = 0,
    this.chunks = const [],
    this.matches = const [],
    this.error,
    this.startedAt,
    this.finishedAt,
    this.selectedModel,
  });

  int get completedChunksCount =>
      chunks.where((c) => c.status == ChunkStatus.match || c.status == ChunkStatus.noMatch).length;

  int get totalMatchesCount => matches.length;

  bool get isFinished =>
      status == ScanStatus.done || status == ScanStatus.stopped || status == ScanStatus.error;

  double get overallProgress {
    if (status == ScanStatus.chunking) {
      return (chunkingProgress / 100.0) * 0.25;
    }
    if (chunkCount == 0) return 0.0;
    final processed = chunks.where((c) =>
        c.status == ChunkStatus.match ||
        c.status == ChunkStatus.noMatch ||
        c.status == ChunkStatus.failed).length;
    return 0.25 + (processed / chunkCount) * 0.75;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'shortPath': shortPath,
    'moviePath': moviePath,
    'shortName': shortName,
    'movieName': movieName,
    'shortSize': shortSize,
    'movieSize': movieSize,
    'shortDuration': shortDuration,
    'movieDuration': movieDuration,
    'chunkCount': chunkCount,
    'chunkingProgress': chunkingProgress,
    'chunks': chunks.map((c) => c.toJson()).toList(),
    'matches': matches.map((m) => m.toJson()).toList(),
    'error': error,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'selectedModel': selectedModel,
  };

  factory Scan.fromJson(Map<String, dynamic> json) => Scan(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: ScanStatus.values.byName(json['status'] as String? ?? 'created'),
    shortPath: json['shortPath'] as String?,
    moviePath: json['moviePath'] as String?,
    shortName: json['shortName'] as String?,
    movieName: json['movieName'] as String?,
    shortSize: json['shortSize'] as int?,
    movieSize: json['movieSize'] as int?,
    shortDuration: (json['shortDuration'] as num?)?.toDouble(),
    movieDuration: (json['movieDuration'] as num?)?.toDouble(),
    chunkCount: (json['chunkCount'] as int?) ?? 0,
    chunkingProgress: (json['chunkingProgress'] as num?)?.toDouble() ?? 0.0,
    chunks: (json['chunks'] as List?)
            ?.map((c) => ChunkState.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [],
    matches: (json['matches'] as List?)
            ?.map((m) => ChunkMatch.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [],
    error: json['error'] as String?,
    startedAt: json['startedAt'] != null
        ? DateTime.parse(json['startedAt'] as String)
        : null,
    finishedAt: json['finishedAt'] != null
        ? DateTime.parse(json['finishedAt'] as String)
        : null,
    selectedModel: json['selectedModel'] as String?,
  );
}
