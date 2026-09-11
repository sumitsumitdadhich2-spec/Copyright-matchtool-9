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

class CandidateEntry {
  final String id;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final String model;
  bool? verified;
  String? verifyReason;
  String? evidence;
  double confidence;
  String? rescanStatus; // 'none' | 'running' | 'found' | 'not_found'
  double? rescanMovieStart;
  double? rescanMovieEnd;

  CandidateEntry({
    required this.id,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.model,
    this.verified,
    this.verifyReason,
    this.evidence,
    this.confidence = 0.9,
    this.rescanStatus = 'none',
    this.rescanMovieStart,
    this.rescanMovieEnd,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'movieStart': movieStart,
    'movieEnd': movieEnd,
    'chunkIndex': chunkIndex,
    'model': model,
    'verified': verified,
    'verifyReason': verifyReason,
    'evidence': evidence,
    'confidence': confidence,
    'rescanStatus': rescanStatus,
    'rescanMovieStart': rescanMovieStart,
    'rescanMovieEnd': rescanMovieEnd,
  };

  factory CandidateEntry.fromJson(Map<String, dynamic> json) => CandidateEntry(
    id: json['id'] as String? ?? 'cand-${json['chunkIndex']}',
    movieStart: (json['movieStart'] as num).toDouble(),
    movieEnd: (json['movieEnd'] as num).toDouble(),
    chunkIndex: json['chunkIndex'] as int? ?? 0,
    model: json['model'] as String? ?? 'gemini-3.7-flash',
    verified: json['verified'] as bool?,
    verifyReason: json['verifyReason'] as String?,
    evidence: json['evidence'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
    rescanStatus: json['rescanStatus'] as String? ?? 'none',
    rescanMovieStart: (json['rescanMovieStart'] as num?)?.toDouble(),
    rescanMovieEnd: (json['rescanMovieEnd'] as num?)?.toDouble(),
  );
}

class CandidateGroup {
  final String id;
  final double shortStart;
  final double shortEnd;
  List<CandidateEntry> candidates;
  int selectedCandidateIndex;
  String status; // 'pending' | 'verified' | 'rejected' | 'rescanning' | 'rescan_found'

  CandidateGroup({
    required this.id,
    required this.shortStart,
    required this.shortEnd,
    required this.candidates,
    this.selectedCandidateIndex = 0,
    this.status = 'pending',
  });

  CandidateEntry? get selectedCandidate =>
      candidates.isNotEmpty && selectedCandidateIndex < candidates.length
          ? candidates[selectedCandidateIndex]
          : null;

  double get duration => (shortEnd - shortStart).abs();

  Map<String, dynamic> toJson() => {
    'id': id,
    'shortStart': shortStart,
    'shortEnd': shortEnd,
    'candidates': candidates.map((c) => c.toJson()).toList(),
    'selectedCandidateIndex': selectedCandidateIndex,
    'status': status,
  };

  factory CandidateGroup.fromJson(Map<String, dynamic> json) => CandidateGroup(
    id: json['id'] as String? ?? 'grp-0',
    shortStart: (json['shortStart'] as num).toDouble(),
    shortEnd: (json['shortEnd'] as num).toDouble(),
    candidates: (json['candidates'] as List<dynamic>?)
            ?.map((e) => CandidateEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    selectedCandidateIndex: json['selectedCandidateIndex'] as int? ?? 0,
    status: json['status'] as String? ?? 'pending',
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
  double confidence;
  String? rescanStatus; // 'none' | 'running' | 'found' | 'not_found'
  double? rescanMovieStart;
  double? rescanMovieEnd;

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
    this.confidence = 0.9,
    this.rescanStatus = 'none',
    this.rescanMovieStart,
    this.rescanMovieEnd,
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
    'confidence': confidence,
    'rescanStatus': rescanStatus,
    'rescanMovieStart': rescanMovieStart,
    'rescanMovieEnd': rescanMovieEnd,
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
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
    rescanStatus: json['rescanStatus'] as String? ?? 'none',
    rescanMovieStart: (json['rescanMovieStart'] as num?)?.toDouble(),
    rescanMovieEnd: (json['rescanMovieEnd'] as num?)?.toDouble(),
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
