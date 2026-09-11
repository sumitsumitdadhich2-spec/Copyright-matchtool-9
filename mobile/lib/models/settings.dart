class AppSettings {
  final String? geminiApiKey;
  final String selectedModel;
  final int maxCpuCores;
  final int chunkSeconds;
  final int scanFps;
  final bool autoVerifyMatches;
  final bool keepChunkFiles;

  const AppSettings({
    this.geminiApiKey,
    this.selectedModel = 'gemini-2.5-flash',
    this.maxCpuCores = 5,
    this.chunkSeconds = 60,
    this.scanFps = 24,
    this.autoVerifyMatches = false,
    this.keepChunkFiles = false,
  });

  bool get hasApiKey => geminiApiKey != null && geminiApiKey!.trim().isNotEmpty;

  AppSettings copyWith({
    String? geminiApiKey,
    String? selectedModel,
    int? maxCpuCores,
    int? chunkSeconds,
    int? scanFps,
    bool? autoVerifyMatches,
    bool? keepChunkFiles,
  }) {
    return AppSettings(
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      maxCpuCores: maxCpuCores ?? this.maxCpuCores,
      chunkSeconds: chunkSeconds ?? this.chunkSeconds,
      scanFps: scanFps ?? this.scanFps,
      autoVerifyMatches: autoVerifyMatches ?? this.autoVerifyMatches,
      keepChunkFiles: keepChunkFiles ?? this.keepChunkFiles,
    );
  }

  Map<String, dynamic> toJson() => {
    'geminiApiKey': geminiApiKey,
    'selectedModel': selectedModel,
    'maxCpuCores': maxCpuCores,
    'chunkSeconds': chunkSeconds,
    'scanFps': scanFps,
    'autoVerifyMatches': autoVerifyMatches,
    'keepChunkFiles': keepChunkFiles,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    geminiApiKey: json['geminiApiKey'] as String?,
    selectedModel: json['selectedModel'] as String? ?? 'gemini-2.5-flash',
    maxCpuCores: (json['maxCpuCores'] as int?) ?? 5,
    chunkSeconds: (json['chunkSeconds'] as int?) ?? 60,
    scanFps: (json['scanFps'] as int?) ?? 24,
    autoVerifyMatches: (json['autoVerifyMatches'] as bool?) ?? false,
    keepChunkFiles: (json['keepChunkFiles'] as bool?) ?? false,
  );
}
