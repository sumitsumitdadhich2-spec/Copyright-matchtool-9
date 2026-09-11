enum ChunkStatus {
  pending,
  scanning,
  noMatch,
  match,
  failed,
  cancelled,
}

class ChunkState {
  final int index;
  ChunkStatus status;
  String? model;
  int attempts;
  List<ChunkMatch> matches;
  String? error;
  String? rawOutput;
  double? duration;

  ChunkState({
    required this.index,
    this.status = ChunkStatus.pending,
    this.model,
    this.attempts = 0,
    this.matches = const [],
    this.error,
    this.rawOutput,
    this.duration,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'status': status.name,
    'model': model,
    'attempts': attempts,
    'matches': matches.map((m) => m.toJson()).toList(),
    'error': error,
    'rawOutput': rawOutput,
    'duration': duration,
  };

  factory ChunkState.fromJson(Map<String, dynamic> json) => ChunkState(
    index: json['index'] as int,
    status: ChunkStatus.values.byName(json['status'] as String? ?? 'pending'),
    model: json['model'] as String?,
    attempts: (json['attempts'] as int?) ?? 0,
    matches: (json['matches'] as List?)
            ?.map((m) => ChunkMatch.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [],
    error: json['error'] as String?,
    rawOutput: json['rawOutput'] as String?,
    duration: (json['duration'] as num?)?.toDouble(),
  );
}

class ChunkMatch {
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  int? chunkIndex;
  String? model;
  bool? verified;
  String? evidence;
  String? reason;

  ChunkMatch({
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    this.chunkIndex,
    this.model,
    this.verified,
    this.evidence,
    this.reason,
  });

  double get duration => (shortEnd - shortStart).abs();
  double get movieDuration => (movieEnd - movieStart).abs();

  Map<String, dynamic> toJson() => {
    'shortStart': shortStart,
    'shortEnd': shortEnd,
    'movieStart': movieStart,
    'movieEnd': movieEnd,
    'chunkIndex': chunkIndex,
    'model': model,
    'verified': verified,
    'evidence': evidence,
    'reason': reason,
  };

  factory ChunkMatch.fromJson(Map<String, dynamic> json) => ChunkMatch(
    shortStart: (json['shortStart'] as num).toDouble(),
    shortEnd: (json['shortEnd'] as num).toDouble(),
    movieStart: (json['movieStart'] as num).toDouble(),
    movieEnd: (json['movieEnd'] as num).toDouble(),
    chunkIndex: json['chunkIndex'] as int?,
    model: json['model'] as String?,
    verified: json['verified'] as bool?,
    evidence: json['evidence'] as String?,
    reason: json['reason'] as String?,
  );
}

class ChunkRawOutput {
  final int chunkIndex;
  final String rawText;
  final DateTime timestamp;
  final int? tokensUsed;

  ChunkRawOutput({
    required this.chunkIndex,
    required this.rawText,
    required this.timestamp,
    this.tokensUsed,
  });

  Map<String, dynamic> toJson() => {
    'chunkIndex': chunkIndex,
    'rawText': rawText,
    'timestamp': timestamp.toIso8601String(),
    'tokensUsed': tokensUsed,
  };

  factory ChunkRawOutput.fromJson(Map<String, dynamic> json) => ChunkRawOutput(
    chunkIndex: json['chunkIndex'] as int,
    rawText: json['rawText'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    tokensUsed: json['tokensUsed'] as int?,
  );
}
