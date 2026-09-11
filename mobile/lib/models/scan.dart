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

class GeminiPrescanUpload {
  final String keyId;
  final String? shortFileUri;
  final String? movieFileUri;
  final String status; // 'pending' | 'uploading' | 'ready' | 'error'
  final String? error;

  GeminiPrescanUpload({
    required this.keyId,
    this.shortFileUri,
    this.movieFileUri,
    this.status = 'pending',
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'keyId': keyId,
    'shortFileUri': shortFileUri,
    'movieFileUri': movieFileUri,
    'status': status,
    'error': error,
  };

  factory GeminiPrescanUpload.fromJson(Map<String, dynamic> json) => GeminiPrescanUpload(
    keyId: json['keyId'] as String? ?? 'key-1',
    shortFileUri: json['shortFileUri'] as String?,
    movieFileUri: json['movieFileUri'] as String?,
    status: json['status'] as String? ?? 'pending',
    error: json['error'] as String?,
  );
}

class GeminiPrescanWindow {
  final int index;
  final double startSec;
  final double endSec;
  String status; // 'pending' | 'scanning' | 'match' | 'no_match' | 'error'
  List<int> matchedMinutes;
  int attempts;
  String? error;

  GeminiPrescanWindow({
    required this.index,
    required this.startSec,
    required this.endSec,
    this.status = 'pending',
    this.matchedMinutes = const [],
    this.attempts = 0,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'startSec': startSec,
    'endSec': endSec,
    'status': status,
    'matchedMinutes': matchedMinutes,
    'attempts': attempts,
    'error': error,
  };

  factory GeminiPrescanWindow.fromJson(Map<String, dynamic> json) => GeminiPrescanWindow(
    index: json['index'] as int? ?? 0,
    startSec: (json['startSec'] as num?)?.toDouble() ?? 0.0,
    endSec: (json['endSec'] as num?)?.toDouble() ?? 1200.0,
    status: json['status'] as String? ?? 'pending',
    matchedMinutes: (json['matchedMinutes'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    attempts: json['attempts'] as int? ?? 0,
    error: json['error'] as String?,
  );
}

class GeminiBackupState {
  String status; // 'idle' | 'running' | 'done' | 'error'
  int gapCount;
  List<int> recoveredMinutes;
  String? error;

  GeminiBackupState({
    this.status = 'idle',
    this.gapCount = 0,
    this.recoveredMinutes = const [],
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'gapCount': gapCount,
    'recoveredMinutes': recoveredMinutes,
    'error': error,
  };

  factory GeminiBackupState.fromJson(Map<String, dynamic> json) => GeminiBackupState(
    status: json['status'] as String? ?? 'idle',
    gapCount: json['gapCount'] as int? ?? 0,
    recoveredMinutes: (json['recoveredMinutes'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    error: json['error'] as String?,
  );
}

class MinuteSuggestion {
  final int minute;
  final int sceneCount;
  final List<String> confidences;

  MinuteSuggestion({
    required this.minute,
    this.sceneCount = 1,
    this.confidences = const ['HIGH'],
  });

  Map<String, dynamic> toJson() => {
    'minute': minute,
    'sceneCount': sceneCount,
    'confidences': confidences,
  };

  factory MinuteSuggestion.fromJson(Map<String, dynamic> json) => MinuteSuggestion(
    minute: json['minute'] as int? ?? 0,
    sceneCount: json['sceneCount'] as int? ?? 1,
    confidences: (json['confidences'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? ['HIGH'],
  );
}

class ShortSegmentState {
  final int index;
  final double start;
  final double end;
  String status; // 'pending' | 'scanning' | 'verifying' | 'done'
  List<ChunkState> chunks;
  bool selected;
  double? movieRangeStart;
  double? movieRangeEnd;
  List<int> movieMinutes;
  String? segmentPath;

  ShortSegmentState({
    required this.index,
    required this.start,
    required this.end,
    this.status = 'pending',
    this.chunks = const [],
    this.selected = true,
    this.movieRangeStart,
    this.movieRangeEnd,
    this.movieMinutes = const [],
    this.segmentPath,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'start': start,
    'end': end,
    'status': status,
    'chunks': chunks.map((c) => c.toJson()).toList(),
    'selected': selected,
    'movieRangeStart': movieRangeStart,
    'movieRangeEnd': movieRangeEnd,
    'movieMinutes': movieMinutes,
    'segmentPath': segmentPath,
  };

  factory ShortSegmentState.fromJson(Map<String, dynamic> json) => ShortSegmentState(
    index: json['index'] as int? ?? 0,
    start: (json['start'] as num?)?.toDouble() ?? 0.0,
    end: (json['end'] as num?)?.toDouble() ?? 60.0,
    status: json['status'] as String? ?? 'pending',
    chunks: (json['chunks'] as List<dynamic>?)
            ?.map((e) => ChunkState.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    selected: json['selected'] as bool? ?? true,
    movieRangeStart: (json['movieRangeStart'] as num?)?.toDouble(),
    movieRangeEnd: (json['movieRangeEnd'] as num?)?.toDouble(),
    movieMinutes: (json['movieMinutes'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    segmentPath: json['segmentPath'] as String?,
  );
}

class RenderJob {
  String status; // 'idle' | 'rendering' | 'done' | 'error'
  double progress;
  String? outputPath;
  String? error;

  RenderJob({
    this.status = 'idle',
    this.progress = 0.0,
    this.outputPath,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'status': status,
    'progress': progress,
    'outputPath': outputPath,
    'error': error,
  };

  factory RenderJob.fromJson(Map<String, dynamic> json) => RenderJob(
    status: json['status'] as String? ?? 'idle',
    progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    outputPath: json['outputPath'] as String?,
    error: json['error'] as String?,
  );
}

class ScanReport {
  final double shortDuration;
  final double totalMatchedSeconds;
  final double matchPercentage;
  final int totalMatchesCount;
  final int verifiedCount;
  final String generatedAt;

  ScanReport({
    required this.shortDuration,
    required this.totalMatchedSeconds,
    required this.matchPercentage,
    required this.totalMatchesCount,
    required this.verifiedCount,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'shortDuration': shortDuration,
    'totalMatchedSeconds': totalMatchedSeconds,
    'matchPercentage': matchPercentage,
    'totalMatchesCount': totalMatchesCount,
    'verifiedCount': verifiedCount,
    'generatedAt': generatedAt,
  };

  factory ScanReport.fromJson(Map<String, dynamic> json) => ScanReport(
    shortDuration: (json['shortDuration'] as num?)?.toDouble() ?? 0.0,
    totalMatchedSeconds: (json['totalMatchedSeconds'] as num?)?.toDouble() ?? 0.0,
    matchPercentage: (json['matchPercentage'] as num?)?.toDouble() ?? 0.0,
    totalMatchesCount: json['totalMatchesCount'] as int? ?? 0,
    verifiedCount: json['verifiedCount'] as int? ?? 0,
    generatedAt: json['generatedAt'] as String? ?? '',
  );
}

class Scan {
  final String id;
  final DateTime createdAt;
  ScanStatus status;
  String? customName;
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
  
  // Short video 1-minute segmenting pipeline state
  List<ShortSegmentState> shortSegments;
  double shortSegmentingProgress;
  int currentShortSegment;

  // Power user features from web dashboard
  bool autoMode;
  bool verifierEnabled;
  String minuteFinderMode; // 'gemini' | 'fast' | 'off'
  double trimStart;
  double? trimEnd;
  List<int> selectedMinutes;
  List<String> logs;
  RenderJob renderJob;
  ScanReport? report;

  // Candidate groups per short segment
  List<CandidateGroup> candidateGroups;

  // Missing-Scene Gap Backup Candidates
  List<dynamic> gapBackupCandidates;

  // Gemini Minute Finder Pipeline State
  String prescanStatus; // 'idle' | 'preparing' | 'uploading' | 'scanning' | 'backup' | 'starting_scan' | 'done' | 'error'
  List<GeminiPrescanUpload> prescanUploads;
  List<GeminiPrescanWindow> prescanWindows;
  GeminiBackupState backupState;
  List<MinuteSuggestion> suggestions;

  Scan({
    required this.id,
    required this.createdAt,
    this.status = ScanStatus.created,
    this.customName,
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
    this.candidateGroups = const [],
    this.gapBackupCandidates = const [],
    this.shortSegments = const [],
    this.shortSegmentingProgress = 0,
    this.currentShortSegment = 0,
    this.error,
    this.startedAt,
    this.finishedAt,
    this.selectedModel,
    this.autoMode = true,
    this.verifierEnabled = true,
    this.minuteFinderMode = 'gemini',
    this.trimStart = 0.0,
    this.trimEnd,
    this.selectedMinutes = const [],
    this.logs = const [],
    RenderJob? renderJob,
    this.report,
    this.prescanStatus = 'idle',
    this.prescanUploads = const [],
    this.prescanWindows = const [],
    GeminiBackupState? backupState,
    this.suggestions = const [],
  })  : renderJob = renderJob ?? RenderJob(),
        backupState = backupState ?? GeminiBackupState();

  int get completedChunksCount =>
      chunks.where((c) => c.status == ChunkStatus.match || c.status == ChunkStatus.noMatch).length;

  int get totalMatchesCount => matches.length;
  int get verifiedMatchesCount => matches.where((m) => m.verified == true).length;

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

  double get coveragePercent {
    if (shortDuration == null || shortDuration! <= 0) return 0.0;
    double matchedSec = 0;
    for (final m in matches) {
      matchedSec += (m.shortEnd - m.shortStart).clamp(0.0, shortDuration!);
    }
    return ((matchedSec / shortDuration!) * 100).clamp(0.0, 100.0);
  }

  List<String> get unmappedGaps {
    if (shortDuration == null || matches.isEmpty) {
      return shortDuration != null ? ['00:00 - ${shortDuration!.toStringAsFixed(0)}s (Full Short)'] : [];
    }
    final List<String> gaps = [];
    double current = 0.0;
    final sorted = List<ChunkMatch>.from(matches)..sort((a, b) => a.shortStart.compareTo(b.shortStart));
    for (final m in sorted) {
      if (m.shortStart > current + 3.0) {
        gaps.add('${current.toStringAsFixed(1)}s - ${m.shortStart.toStringAsFixed(1)}s');
      }
      current = current > m.shortEnd ? current : m.shortEnd;
    }
    if (shortDuration! > current + 3.0) {
      gaps.add('${current.toStringAsFixed(1)}s - ${shortDuration!.toStringAsFixed(1)}s');
    }
    return gaps;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'customName': customName,
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
    'shortSegments': shortSegments.map((s) => s.toJson()).toList(),
    'shortSegmentingProgress': shortSegmentingProgress,
    'currentShortSegment': currentShortSegment,
    'matches': matches.map((m) => m.toJson()).toList(),
    'candidateGroups': candidateGroups.map((g) => g.toJson()).toList(),
    'error': error,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'selectedModel': selectedModel,
    'autoMode': autoMode,
    'verifierEnabled': verifierEnabled,
    'minuteFinderMode': minuteFinderMode,
    'trimStart': trimStart,
    'trimEnd': trimEnd,
    'selectedMinutes': selectedMinutes,
    'logs': logs,
    'renderJob': renderJob.toJson(),
    'report': report?.toJson(),
    'prescanStatus': prescanStatus,
    'prescanUploads': prescanUploads.map((u) => u.toJson()).toList(),
    'prescanWindows': prescanWindows.map((w) => w.toJson()).toList(),
    'backupState': backupState.toJson(),
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
  };

  factory Scan.fromJson(Map<String, dynamic> json) => Scan(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: ScanStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ScanStatus.created,
    ),
    customName: json['customName'] as String?,
    shortPath: json['shortPath'] as String?,
    moviePath: json['moviePath'] as String?,
    shortName: json['shortName'] as String?,
    movieName: json['movieName'] as String?,
    shortSize: json['shortSize'] as int?,
    movieSize: json['movieSize'] as int?,
    shortDuration: (json['shortDuration'] as num?)?.toDouble(),
    movieDuration: (json['movieDuration'] as num?)?.toDouble(),
    chunkCount: json['chunkCount'] as int? ?? 0,
    chunkingProgress: (json['chunkingProgress'] as num?)?.toDouble() ?? 0.0,
    chunks: (json['chunks'] as List<dynamic>?)
            ?.map((e) => ChunkState.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    shortSegments: (json['shortSegments'] as List<dynamic>?)
            ?.map((e) => ShortSegmentState.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    shortSegmentingProgress: (json['shortSegmentingProgress'] as num?)?.toDouble() ?? 0.0,
    currentShortSegment: json['currentShortSegment'] as int? ?? 0,
    matches: (json['matches'] as List<dynamic>?)
            ?.map((e) => ChunkMatch.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    candidateGroups: (json['candidateGroups'] as List<dynamic>?)
            ?.map((e) => CandidateGroup.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    error: json['error'] as String?,
    startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'] as String) : null,
    finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt'] as String) : null,
    selectedModel: json['selectedModel'] as String?,
    autoMode: json['autoMode'] as bool? ?? true,
    verifierEnabled: json['verifierEnabled'] as bool? ?? true,
    minuteFinderMode: json['minuteFinderMode'] as String? ?? 'gemini',
    trimStart: (json['trimStart'] as num?)?.toDouble() ?? 0.0,
    trimEnd: (json['trimEnd'] as num?)?.toDouble(),
    selectedMinutes: (json['selectedMinutes'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [],
    logs: (json['logs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    renderJob: json['renderJob'] != null
        ? RenderJob.fromJson(json['renderJob'] as Map<String, dynamic>)
        : RenderJob(),
    report: json['report'] != null
        ? ScanReport.fromJson(json['report'] as Map<String, dynamic>)
        : null,
    prescanStatus: json['prescanStatus'] as String? ?? 'idle',
    prescanUploads: (json['prescanUploads'] as List<dynamic>?)
            ?.map((e) => GeminiPrescanUpload.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    prescanWindows: (json['prescanWindows'] as List<dynamic>?)
            ?.map((e) => GeminiPrescanWindow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    backupState: json['backupState'] != null
        ? GeminiBackupState.fromJson(json['backupState'] as Map<String, dynamic>)
        : GeminiBackupState(),
    suggestions: (json['suggestions'] as List<dynamic>?)
            ?.map((e) => MinuteSuggestion.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
