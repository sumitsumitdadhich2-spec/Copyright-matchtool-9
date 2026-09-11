/// Exact model definitions copied verbatim from web app's `lib/models.ts`.
/// All pools, TPM limits, token calculations, and rate limits match the web app.

class ModelSpec {
  final String id;
  final int rpm;
  final int rpd;
  final String role;
  final String description;

  const ModelSpec({
    required this.id,
    required this.rpm,
    required this.rpd,
    required this.role,
    this.description = '',
  });

  String get displayName => id.replaceAll('gemini-', '').replaceAll(RegExp(r'flash', caseSensitive: false), 'shiva');
}

class AppModels {
  /// CHUNK-MAP models (locked): gemini-3.6-flash, gemini-3.7-flash, gemini-3.8-flash
  /// Allowed to run chunk-time mapping requests.
  static const List<ModelSpec> chunkModelPool = [
    ModelSpec(
      id: 'gemini-3.6-flash',
      rpm: 5,
      rpd: 20,
      role: 'Chunk Mapper',
      description: 'Robust baseline scene comparison',
    ),
    ModelSpec(
      id: 'gemini-3.7-flash',
      rpm: 5,
      rpd: 20,
      role: 'Chunk Mapper (Recommended)',
      description: 'Fast, balanced high-accuracy forensic',
    ),
    ModelSpec(
      id: 'gemini-3.8-flash',
      rpm: 5,
      rpd: 20,
      role: 'Chunk Mapper',
      description: 'Deep forensic multi-frame analysis',
    ),
  ];

  /// VERIFY models (locked): gemini-3.5-flash-lite + gemini-3.1-flash-lite ONLY.
  /// Daily limit 500 RPD each - high throughput verification at 24fps.
  static const List<ModelSpec> verifyModelPool = [
    ModelSpec(
      id: 'gemini-3.5-flash-lite',
      rpm: 15,
      rpd: 500,
      role: '24fps Verifier (500 RPD)',
      description: 'High daily quota verification',
    ),
    ModelSpec(
      id: 'gemini-3.1-flash-lite',
      rpm: 15,
      rpd: 500,
      role: '24fps Verifier (500 RPD)',
      description: 'High daily quota verification',
    ),
  ];

  /// RESCAN models (primary): gemini-3-flash-preview and gemini-3.5-flash
  static const List<ModelSpec> rescanModelPool = [
    ModelSpec(
      id: 'gemini-3-flash-preview',
      rpm: 5,
      rpd: 20,
      role: 'Rescan Primary',
      description: 'Full-chunk segment hunt preview',
    ),
    ModelSpec(
      id: 'gemini-3.5-flash',
      rpm: 5,
      rpd: 20,
      role: 'Rescan Primary',
      description: 'Precision chunk matcher',
    ),
  ];

  /// RESCAN BACKUP models: fallback when primary rescan limit exhausts
  static const List<ModelSpec> rescanBackupPool = [
    ModelSpec(
      id: 'gemini-3.5-flash-lite',
      rpm: 15,
      rpd: 500,
      role: 'Rescan Backup (500 RPD)',
      description: 'High quota fallback',
    ),
    ModelSpec(
      id: 'gemini-3.1-flash-lite',
      rpm: 15,
      rpd: 500,
      role: 'Rescan Backup (500 RPD)',
      description: 'High quota fallback',
    ),
  ];

  /// Full combined pool
  static List<ModelSpec> get allModels {
    final list = <ModelSpec>[
      ...chunkModelPool,
      ...verifyModelPool,
      ...rescanModelPool,
    ];
    final seen = <String>{};
    return list.where((m) => seen.add(m.id)).toList();
  }

  /// Default model for chunk mapping
  static const String defaultChunkModel = 'gemini-3.7-flash';

  /// Default model for 24fps verification
  static const String defaultVerifyModel = 'gemini-3.5-flash-lite';

  /// Free-tier TPM cap shared by models
  static const int tpmLimit = 250000;

  /// Measured token cost per video frame at default resolution (from web app lib/models.ts)
  static const int tokensPerFrame = 65;

  /// Cinematic forensic FPS (24 fps)
  static const int scanFps = 24;

  /// Model min interval between requests (60s cooldown for TPM limit)
  static const int modelMinIntervalMs = 60000;

  /// Maximum output tokens for requests
  static const int maxOutputTokens = 65536;

  /// Estimate token cost from total video seconds @ 24 fps
  static int estimateRequestTokens(double totalVideoSeconds) {
    return (totalVideoSeconds * scanFps * tokensPerFrame).ceil() + 2000;
  }

  /// Pacing interval in milliseconds
  static int pacingIntervalMs(double totalVideoSeconds) {
    final tokens = estimateRequestTokens(totalVideoSeconds);
    final ms = ((tokens / tpmLimit) * 60000).ceil();
    return ms.clamp(3000, modelMinIntervalMs);
  }
}
