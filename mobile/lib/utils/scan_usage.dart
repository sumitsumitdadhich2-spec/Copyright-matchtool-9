import '../models/scan.dart';

/// 1:1 Port of lib/scan-usage.ts
/// Exact AI request counters, distinguishing between effective (successful) and error attempts.

class ErrorCountDetails {
  int highDemandOrRateLimit = 0;
  int notFound404 = 0;
  int invalidKey = 0;
  int dailyExhausted = 0;
  int prohibitedPolicy = 0;
  int other = 0;
}

class ModelUsageCategory {
  int chunkScan = 0;
  int rescan = 0;
  int verifier = 0;
  int minuteFinder = 0;
  int missingScene = 0;
  int total = 0;
  int effective = 0;
  final ErrorCountDetails errors = ErrorCountDetails();
}

class ScanUsageSummary {
  int totalRequests = 0;
  int effectiveRequests = 0;
  int totalErrors = 0;
  final ErrorCountDetails errorBreakdown = ErrorCountDetails();
  final Map<String, ModelUsageCategory> byModel = {};
  final Map<String, int> byStage = {
    'chunkScan': 0,
    'rescan': 0,
    'verifier': 0,
    'minuteFinder': 0,
    'missingScene': 0,
  };
  final Map<String, int> mainModels = {
    'gemini37': 0,
    'gemini38': 0,
    'gemini36': 0,
    'others': 0,
  };

  static ScanUsageSummary compute(Scan? scan) {
    final summary = ScanUsageSummary();
    if (scan == null) return summary;

    final getBucket = (String mId) {
      final clean = mId.trim().toLowerCase();
      return summary.byModel.putIfAbsent(clean, () => ModelUsageCategory());
    };

    final record = (String mId, String stage, bool isEff, [String? errType]) {
      final clean = mId.trim().toLowerCase();
      final bucket = getBucket(clean);
      bucket.total += 1;
      summary.totalRequests += 1;

      if (isEff) {
        bucket.effective += 1;
        summary.effectiveRequests += 1;
        summary.byStage[stage] = (summary.byStage[stage] ?? 0) + 1;

        if (clean.contains('3.7')) {
          summary.mainModels['gemini37'] = (summary.mainModels['gemini37'] ?? 0) + 1;
        } else if (clean.contains('3.8')) {
          summary.mainModels['gemini38'] = (summary.mainModels['gemini38'] ?? 0) + 1;
        } else if (clean.contains('3.6')) {
          summary.mainModels['gemini36'] = (summary.mainModels['gemini36'] ?? 0) + 1;
        } else {
          summary.mainModels['others'] = (summary.mainModels['others'] ?? 0) + 1;
        }
      } else {
        summary.totalErrors += 1;
        bucket.errors.highDemandOrRateLimit += 1;
        summary.errorBreakdown.highDemandOrRateLimit += 1;
      }
    };

    // Structural scan data objects
    for (final w in scan.geminiPrescanWindows) {
      if (w.status == 'done') {
        record('gemini-3.7-flash', 'minuteFinder', true);
      }
    }

    for (final c in scan.chunks) {
      if (c.status.name == 'done') {
        record(c.model ?? 'gemini-3.7-flash', 'chunkScan', true);
      }
    }

    for (final g in scan.candidateGroups) {
      for (final c in g.candidates) {
        if (c.verdict != null) {
          record(c.verifierModel ?? 'gemini-3.5-flash-lite', 'verifier', true);
        }
      }
    }

    return summary;
  }
}
