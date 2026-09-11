class ModelSpec {
  final String id;
  final String displayName;
  final int rpm;
  final int rpd;
  final String description;

  const ModelSpec({
    required this.id,
    required this.displayName,
    required this.rpm,
    required this.rpd,
    required this.description,
  });
}

class AppConstants {
  static const String appName = 'Shiva MatchTool';
  static const String appSubtitle = 'Forensic AI Video Scanner · 24 fps';
  static const String appVersion = '1.0.0';

  // Hardware & Processing Limits
  static const int maxCpuCores = 5; // CRITICAL: Never exceed 5 CPU cores on mobile
  static const int scanFps = 24; // Standard cinematic forensic FPS
  static const int chunkSeconds = 60; // 1-minute chunks

  // ===========================================================================
  // MODEL POOLS - Locked 100% identical to web lib/models.ts
  // ===========================================================================

  /// CHUNK-MAP models (locked): gemini-3.6-flash, gemini-3.7-flash, gemini-3.8-flash.
  static const List<ModelSpec> chunkModelPool = [
    ModelSpec(id: 'gemini-3.7-flash', displayName: '3.7-shiva', rpm: 5, rpd: 20, description: 'Fast, balanced high-accuracy forensic'),
    ModelSpec(id: 'gemini-3.8-flash', displayName: '3.8-shiva', rpm: 5, rpd: 20, description: 'Deep forensic multi-frame analysis'),
    ModelSpec(id: 'gemini-3.6-flash', displayName: '3.6-shiva', rpm: 5, rpd: 20, description: 'Robust baseline scene comparison'),
  ];

  /// VERIFY models (locked): gemini-3.5-flash-lite + gemini-3.1-flash-lite ONLY (500 RPD each).
  static const List<ModelSpec> verifyModelPool = [
    ModelSpec(id: 'gemini-3.5-flash-lite', displayName: '3.5-shiva-lite', rpm: 15, rpd: 500, description: 'High daily quota (500 RPD) candidate verifier'),
    ModelSpec(id: 'gemini-3.1-flash-lite', displayName: '3.1-shiva-lite', rpm: 15, rpd: 500, description: 'High daily quota (500 RPD) candidate verifier'),
  ];

  /// RESCAN models (primary): gemini-3-flash-preview and gemini-3.5-flash run rescan requests.
  static const List<ModelSpec> rescanModelPool = [
    ModelSpec(id: 'gemini-3-flash-preview', displayName: '3-shiva-preview', rpm: 5, rpd: 20, description: 'Full-chunk deep segment hunt'),
    ModelSpec(id: 'gemini-3.5-flash', displayName: '3.5-shiva', rpm: 5, rpd: 20, description: 'Precision segment rescan'),
  ];

  /// RESCAN BACKUP models: fallback when primary rescan limit is reached.
  static const List<ModelSpec> rescanBackupPool = [
    ModelSpec(id: 'gemini-3.5-flash-lite', displayName: '3.5-shiva-lite', rpm: 15, rpd: 500, description: 'Fallback high-limit rescan'),
    ModelSpec(id: 'gemini-3.1-flash-lite', displayName: '3.1-shiva-lite', rpm: 15, rpd: 500, description: 'Fallback high-limit rescan'),
  ];

  /// MINUTE FINDER models (20-min window pre-scan)
  static const List<ModelSpec> minuteFinderModelPool = [
    ModelSpec(id: 'gemini-3.7-flash', displayName: '3.7-shiva', rpm: 5, rpd: 20, description: 'Fast 20-min window pre-scan'),
    ModelSpec(id: 'gemini-3.8-flash', displayName: '3.8-shiva', rpm: 5, rpd: 20, description: 'Deep 20-min window pre-scan'),
    ModelSpec(id: 'gemini-3.6-flash', displayName: '3.6-shiva', rpm: 5, rpd: 20, description: 'Baseline 20-min window pre-scan'),
  ];

  /// BACKUP MINUTE FINDER models (gap recovery pass)
  static const List<ModelSpec> backupMinuteFinderModelPool = [
    ModelSpec(id: 'gemini-3.7-flash', displayName: '3.7-shiva', rpm: 5, rpd: 20, description: 'High-FPS gap recovery'),
    ModelSpec(id: 'gemini-3.8-flash', displayName: '3.8-shiva', rpm: 5, rpd: 20, description: 'Deep multi-frame gap recovery'),
    ModelSpec(id: 'gemini-3.6-flash', displayName: '3.6-shiva', rpm: 5, rpd: 20, description: 'Robust gap recovery'),
  ];

  static const String defaultModel = 'gemini-3.7-flash';
  static const String defaultVerifyModel = 'gemini-3.5-flash-lite';
  static const String defaultRescanModel = 'gemini-3-flash-preview';

  static const List<String> availableModels = [
    'gemini-3.7-flash',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
    'gemini-3-flash-preview',
  ];

  // Storage Keys
  static const String prefApiKey = 'gemini_api_key';
  static const String prefSelectedModel = 'selected_model';
  static const String prefAutoVerify = 'auto_verify_matches';
  static const String prefKeepChunks = 'keep_chunk_files';

  // Colors / Theme Anchors
  static const int backgroundColorValue = 0xFF0F0F0F;
  static const int surfaceColorValue = 0xFF1A1A1A;
  static const int cardColorValue = 0xFF202020;
  static const int primaryColorValue = 0xFF6366F1;
  static const int accentAmberValue = 0xFFF59E0B;
  static const int successGreenValue = 0xFF22C55E;
  static const int errorRedValue = 0xFFEF4444;

  static String displayModelName(String modelId) {
    return modelId.replaceAll('gemini-', '').replaceAll(RegExp(r'flash', caseSensitive: false), 'shiva');
  }
}
