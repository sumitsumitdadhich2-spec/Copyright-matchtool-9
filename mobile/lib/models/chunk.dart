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

class UserPick {
  final int index;
  final bool viaRescan;
  final int at;

  UserPick({
    required this.index,
    required this.viaRescan,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'viaRescan': viaRescan,
    'at': at,
  };

  factory UserPick.fromJson(Map<String, dynamic> json) => UserPick(
    index: json['index'] as int? ?? 0,
    viaRescan: json['viaRescan'] as bool? ?? false,
    at: json['at'] as int? ?? 0,
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
  String? source;
  int? rank;
  bool? userPick;
  String? batchVerified;
  String? batchVerifierReason;
  String? batchCropPosition;
  String? batchProof;
  bool? rescanRequired;
  double? shortStart;
  double? shortEnd;
  bool? rejected;
  String? verdict;
  String? reason;

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
    this.source,
    this.rank,
    this.userPick,
    this.batchVerified,
    this.batchVerifierReason,
    this.batchCropPosition,
    this.batchProof,
    this.rescanRequired,
    this.shortStart,
    this.shortEnd,
    this.rejected,
    this.verdict,
    this.reason,
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
    'source': source,
    'rank': rank,
    'userPick': userPick,
    'batchVerified': batchVerified,
    'batchVerifierReason': batchVerifierReason,
    'batchCropPosition': batchCropPosition,
    'batchProof': batchProof,
    'rescanRequired': rescanRequired,
    'shortStart': shortStart,
    'shortEnd': shortEnd,
    'rejected': rejected,
    'verdict': verdict,
    'reason': reason,
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
    source: json['source'] as String?,
    rank: json['rank'] as int?,
    userPick: json['userPick'] as bool?,
    batchVerified: json['batchVerified'] as String?,
    batchVerifierReason: json['batchVerifierReason'] as String?,
    batchCropPosition: json['batchCropPosition'] as String?,
    batchProof: json['batchProof'] as String?,
    rescanRequired: json['rescanRequired'] as bool?,
    shortStart: (json['shortStart'] as num?)?.toDouble(),
    shortEnd: (json['shortEnd'] as num?)?.toDouble(),
    rejected: json['rejected'] as bool?,
    verdict: json['verdict'] as String?,
    reason: json['reason'] as String?,
  );
}

class CandidateGroup {
  final String id;
  final double shortStart;
  final double shortEnd;
  List<CandidateEntry> candidates;
  int selectedCandidateIndex;
  String status; // 'pending' | 'verified' | 'rejected' | 'rescanning' | 'rescan_found' | 'confirmed'
  String? userPickId;
  String? confirmedMatchId;
  String? state;
  String? origin;
  dynamic userPick;
  String? originWindow;
  int? confirmedIndex;
  bool? confirmedViaRescan;
  int? attempts;

  CandidateGroup({
    required this.id,
    required this.shortStart,
    required this.shortEnd,
    required this.candidates,
    this.selectedCandidateIndex = 0,
    this.status = 'pending',
    this.userPickId,
    this.confirmedMatchId,
    this.state,
    this.origin,
    this.userPick,
    this.originWindow,
    this.confirmedIndex,
    this.confirmedViaRescan,
    this.attempts,
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
    'userPickId': userPickId,
    'confirmedMatchId': confirmedMatchId,
    'state': state,
    'origin': origin,
    'userPick': userPick is UserPick ? (userPick as UserPick).toJson() : userPick,
    'originWindow': originWindow,
    'confirmedIndex': confirmedIndex,
    'confirmedViaRescan': confirmedViaRescan,
    'attempts': attempts,
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
    userPickId: json['userPickId'] as String?,
    confirmedMatchId: json['confirmedMatchId'] as String?,
    state: json['state'] as String?,
    origin: json['origin'] as String?,
    userPick: json['userPick'] != null
        ? (json['userPick'] is Map<String, dynamic>
            ? UserPick.fromJson(json['userPick'] as Map<String, dynamic>)
            : json['userPick'])
        : null,
    originWindow: json['originWindow'] as String?,
    confirmedIndex: json['confirmedIndex'] as int?,
    confirmedViaRescan: json['confirmedViaRescan'] as bool?,
    attempts: json['attempts'] as int?,
  );
}

class ChunkMatch {
  String? id;
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
  String? origin;
  bool? userPick;
  bool? viaRescan;
  String? batchVerified;
  String? batchVerifierReason;
  String? batchCropPosition;
  String? batchProof;
  bool? rescanRequired;
  bool? rejectedKept;
  String? originWindow;
  bool? rejected;

  ChunkMatch({
    this.id,
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
    this.origin,
    this.userPick,
    this.viaRescan,
    this.batchVerified,
    this.batchVerifierReason,
    this.batchCropPosition,
    this.batchProof,
    this.rescanRequired,
    this.rejectedKept,
    this.originWindow,
    this.rejected,
  });

  double get duration => (shortEnd - shortStart).abs();
  double get movieDuration => (movieEnd - movieStart).abs();

  Map<String, dynamic> toJson() => {
    'id': id,
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
    'origin': origin,
    'userPick': userPick,
    'viaRescan': viaRescan,
    'batchVerified': batchVerified,
    'batchVerifierReason': batchVerifierReason,
    'batchCropPosition': batchCropPosition,
    'batchProof': batchProof,
    'rescanRequired': rescanRequired,
    'rejectedKept': rejectedKept,
    'originWindow': originWindow,
    'rejected': rejected,
  };

  factory ChunkMatch.fromJson(Map<String, dynamic> json) => ChunkMatch(
    id: json['id'] as String?,
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
    origin: json['origin'] as String?,
    userPick: json['userPick'] as bool?,
    viaRescan: json['viaRescan'] as bool?,
    batchVerified: json['batchVerified'] as String?,
    batchVerifierReason: json['batchVerifierReason'] as String?,
    batchCropPosition: json['batchCropPosition'] as String?,
    batchProof: json['batchProof'] as String?,
    rescanRequired: json['rescanRequired'] as bool?,
    rejectedKept: json['rejectedKept'] as bool?,
    originWindow: json['originWindow'] as String?,
    rejected: json['rejected'] as bool?,
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
