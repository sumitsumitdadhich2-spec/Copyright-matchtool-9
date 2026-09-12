import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../services/settings_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'token_badge_widget.dart';
import 'users_dialog.dart';
import 'settings_dialog.dart';
import 'upload_panel.dart';
import 'top_milestone_banner.dart';
import 'live_activity_bar.dart';
import 'trim_panel.dart';
import 'twelvelabs_panel.dart';
import 'minute_finder_panel.dart';
import 'minute_select_panel.dart';
import 'model_board.dart';
import 'scan_timeline.dart';
import 'minute_approval.dart';
import 'chunk_results_panel.dart';
import 'candidates_panel.dart';
import 'batch_verifier_panel.dart';
import 'compare_studio_panel.dart';
import 'gap_backup_panel.dart';
import 'render_panel.dart';
import 'report_panel.dart';
import 'scan_usage_report.dart';
import 'logs_panel.dart';
import 'history_panel.dart';
import 'error_boundary_widget.dart';

/// 1:1 Port of components/cmt/dashboard.tsx
/// The central orchestrator dashboard bringing all panels together.

class DashboardWidget extends StatefulWidget {
  const DashboardWidget({super.key});

  @override
  State<DashboardWidget> createState() => _DashboardWidgetState();
}

class _DashboardWidgetState extends State<DashboardWidget> {
  final ScrollController _scrollController = ScrollController();

  void _scrollToLogs() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanService = context.watch<ScanService>();
    final settingsService = context.watch<SettingsService>();
    final sessionService = context.watch<SessionService>();
    final scan = scanService.currentScan;
    final user = sessionService.user;

    final isScanning = scanService.isScanning;
    final verifierOn = scan?.verifierEnabled ?? settingsService.verifierEnabled;
    final autoModeOn = scan?.autoMode ?? settingsService.autoMode;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.hub, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              scan?.customName ?? scan?.shortName ?? 'CMT Studio',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          const TokenBadgeWidget(),
          const SizedBox(width: 6),
          // Verifier toggle
          IconButton(
            icon: Icon(verifierOn ? Icons.shield : Icons.shield_outlined, size: 20),
            color: verifierOn ? AppTheme.success : AppTheme.textMuted,
            tooltip: '24fps AI Verifier: ${verifierOn ? "ON" : "OFF"}',
            onPressed: () => scanService.toggleVerifier(),
          ),
          // Auto mode toggle
          IconButton(
            icon: Icon(autoModeOn ? Icons.bolt : Icons.flash_off, size: 20),
            color: autoModeOn ? const Color(0xFFF59E0B) : AppTheme.textMuted,
            tooltip: 'Auto Mode: ${autoModeOn ? "ON" : "OFF"}',
            onPressed: () => scanService.toggleAutoMode(),
          ),
          if (user?.role == 'admin')
            IconButton(
              icon: const Icon(Icons.people_outline, size: 20),
              tooltip: 'User Management',
              onPressed: () => showDialog(context: context, builder: (_) => const UsersDialog()),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings & API Keys',
            onPressed: () => SettingsDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: 'History',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppTheme.card,
                builder: (ctx) => DraggableScrollableSheet(
                  initialChildSize: 0.85,
                  maxChildSize: 0.95,
                  minChildSize: 0.5,
                  builder: (_, scrollCtrl) => HistoryPanelWidget(
                    onNewScan: () => Navigator.pop(ctx),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        children: [
          // Upload Panel
          ErrorBoundaryWidget(
            fallbackTitle: 'Upload Panel Error',
            child: UploadPanel(
              scan: scan,
              selectedScanId: scan?.id,
              onScanCreated: (id) => scanService.loadScan(id),
              refresh: () => scanService.refreshCurrentScan(),
            ),
          ),

          // Milestone & Live Activity
          if (scan != null) ...[
            ErrorBoundaryWidget(
              fallbackTitle: 'Milestone Banner Error',
              child: TopMilestoneBanner(scan: scan),
            ),
            const SizedBox(height: 8),
            ErrorBoundaryWidget(
              fallbackTitle: 'Live Activity Bar Error',
              child: LiveActivityBar(scan: scan, onScrollToLogs: _scrollToLogs),
            ),
            const SizedBox(height: 8),
          ],

          // Video Trimmer
          if (scan?.movieDuration != null)
            ErrorBoundaryWidget(
              fallbackTitle: 'Trim Panel Error',
              child: TrimPanel(scan: scan!),
            ),

          // TwelveLabs & Minute Finder
          if (scan != null) ...[
            ErrorBoundaryWidget(
              fallbackTitle: 'TwelveLabs Panel Error',
              child: TwelveLabsPanel(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Minute Finder Error',
              child: MinuteFinderPanel(scan: scan),
            ),
            if (scan.shortSegments.isNotEmpty || scan.shortDuration > 0)
              ErrorBoundaryWidget(
                fallbackTitle: 'Minute Select Error',
                child: MinuteSelectPanel(scan: scan),
              ),
          ],

          // Scan Timeline & Multi-Model Board
          if (scan != null) ...[
            ErrorBoundaryWidget(
              fallbackTitle: 'Model Board Error',
              child: ModelBoard(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Scan Timeline Error',
              child: ScanTimeline(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Chunk Results Panel Error',
              child: ChunkResultsPanel(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Candidates Panel Error',
              child: CandidatesPanel(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Batch Verifier Error',
              child: BatchVerifierPanel(scan: scan),
            ),
          ],

          // Side-by-Side Compare Studio
          if (scan != null)
            ErrorBoundaryWidget(
              fallbackTitle: 'Compare Panel Error',
              child: CompareStudioPanel(scan: scan),
            ),

          // Gap Backup Panel
          if (scan != null)
            ErrorBoundaryWidget(
              fallbackTitle: 'Gap Backup Error',
              child: GapBackupPanel(scan: scan),
            ),

          // Render, Report & Usage Panels
          if (scan != null) ...[
            ErrorBoundaryWidget(
              fallbackTitle: 'Render Panel Error',
              child: RenderPanel(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Report Panel Error',
              child: ReportPanel(scan: scan),
            ),
            ErrorBoundaryWidget(
              fallbackTitle: 'Usage Report Error',
              child: ScanUsageReportWidget(scan: scan),
            ),
          ],

          // Live Logs Panel
          if (scan != null)
            ErrorBoundaryWidget(
              fallbackTitle: 'Logs Panel Error',
              child: LogsPanel(scan: scan),
            ),
        ],
      ),
    );
  }
}
