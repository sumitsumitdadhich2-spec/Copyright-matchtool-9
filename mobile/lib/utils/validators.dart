class Validators {
  static bool isValidApiKey(String? key) {
    if (key == null) return false;
    final trimmed = key.trim();
    return trimmed.length >= 30 && trimmed.startsWith('AIza');
  }

  static bool isSupportedVideo(String? path) {
    if (path == null) return false;
    final ext = path.toLowerCase().split('.').last;
    return ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'ts'].contains(ext);
  }

  static String? validateApiKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Gemini API key is required';
    }
    if (value.trim().length < 25) {
      return 'Invalid API key format (too short)';
    }
    return null;
  }
}
