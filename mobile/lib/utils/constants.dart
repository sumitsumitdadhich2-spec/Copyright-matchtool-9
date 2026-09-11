class AppConstants {
  static const String appName = 'Shiva MatchTool';
  static const String appSubtitle = 'Forensic AI Video Scanner · 24 fps';
  static const String appVersion = '1.0.0';

  // Hardware & Processing Limits
  static const int maxCpuCores = 5; // CRITICAL: Never exceed 5 CPU cores on mobile
  static const int scanFps = 24; // Standard cinematic forensic FPS
  static const int chunkSeconds = 60; // 1-minute chunks

  // AI Models
  static const String defaultModel = 'gemini-2.5-flash';
  static const List<String> availableModels = [
    'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
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
}
