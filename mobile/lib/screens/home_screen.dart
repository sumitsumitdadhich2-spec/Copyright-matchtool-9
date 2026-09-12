import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../services/scan_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../widgets/top_milestone_banner.dart';
import '../widgets/live_activity_bar.dart';
import '../widgets/model_board.dart';
import '../widgets/chunk_timeline_widget.dart';
import '../widgets/chunk_results_panel.dart';
import '../widgets/candidates_panel.dart';
import '../widgets/candidate_chooser_widget.dart';
import '../widgets/minute_finder_panel.dart';
import '../widgets/minute_approval_widget.dart';
import '../widgets/short_coverage_widget.dart';
import '../widgets/twelvelabs_panel.dart';
import '../widgets/missing_scene_panel.dart';
import '../widgets/scan_usage_report.dart';
import '../widgets/scan_timing_report.dart';
import '../widgets/compare_studio_panel.dart';
import '../widgets/batch_verifier_panel.dart';
import '../widgets/gap_backup_panel.dart';
import '../widgets/render_panel.dart';
import '../widgets/report_panel.dart';
import '../widgets/logs_panel.dart';
import '../widgets/trim_panel.dart';
import '../widgets/minute_select_panel.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import '../widgets/auth_gate.dart';
import '../widgets/users_dialog.dart';
import '../widgets/token_badge_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Local upload state for the studio tab
  String? _shortPath;
  String? _shortName;
  String? _moviePath;
  String? _movieName;
  bool _creatingScan = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _selectedTabIndex = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickShortVideo() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
      if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
        setState(() {
          _shortPath = res.files.first.path;
          _shortName = res.files.first.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking short: $e')));
    }
  }

  Future<void> _pickMovieVideo() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
      if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
        setState(() {
          _moviePath = res.files.first.path;
          _movieName = res.files.first.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking movie: $e')));
    }
  }

  Future<void> _createNewScan(ScanService scanService, SettingsService settings) async {
    if (_shortPath == null || _moviePath == null) return;
    if (!settings.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Gemini API key is required. Please set it in Settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ),
      );
      return;
    }

    setState(() => _creatingScan = true);
    scanService.configureGemini(settings.apiKey, model: settings.selectedModel);
    final scan = await scanService.createScan(
      shortPath: _shortPath!,
      moviePath: _moviePath!,
      selectedModel: settings.selectedModel,
    );
    setState(() => _creatingScan = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Created Scan for: ${scan.shortName}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final scanService = context.watch<ScanService>();
    final activeScan = scanService.currentScan;
    final isScanning = scanService.isScanning;

    final autoOn = activeScan?.autoMode ?? true;
    final verifierOn = activeScan?.verifierEnabled ?? true;
    final auth = AuthGate.maybeOf(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.radar, color: Color(0xFFF59E0B), size: 20),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shiva MatchTool',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '24fps Forensic • 100% Local On-Device',
                    style: TextStyle(fontSize: 9, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Live Token Balance Badge
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: TokenBadgeWidget(),
          ),
          const SizedBox(width: 4),

          // Admin User Management
          if (auth?.user.role == 'admin')
            IconButton(
              icon: const Icon(Icons.people_outline, size: 20),
              tooltip: 'Manage Users (Admin)',
              onPressed: () => UsersDialog.show(context),
            ),

          // Quick Auto Mode Toggle
          IconButton(
            icon: Icon(
              autoOn ? Icons.flash_on : Icons.flash_off,
              size: 20,
              color: autoOn ? const Color(0xFF38BDF8) : Colors.white38,
            ),
            tooltip: 'Auto Mode: ${autoOn ? "ON" : "OFF"}',
            onPressed: activeScan != null ? () => scanService.toggleAutoMode() : null,
          ),
          // Quick Verifier Toggle
          IconButton(
            icon: Icon(
              verifierOn ? Icons.shield : Icons.shield_outlined,
              size: 20,
              color: verifierOn ? const Color(0xFF10B981) : Colors.white38,
            ),
            tooltip: '24fps AI Verifier: ${verifierOn ? "ON" : "OFF"}',
            onPressed: activeScan != null ? () => scanService.toggleVerifier() : null,
          ),
          // Past Scans
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: 'Scan History',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          // Settings
          IconButton(
            icon: Icon(
              Icons.settings,
              size: 20,
              color: settings.hasApiKey ? Colors.white : Colors.amberAccent,
            ),
            tooltip: 'Settings (API Keys & Hardware)',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          // Logout Button
          if (auth != null)
            IconButton(
              icon: const Icon(Icons.logout, size: 18, color: Colors.white54),
              tooltip: 'Sign Out (${auth.user.username})',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: Text('Sign out of account "${auth.user.username}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await auth.logout();
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF38BDF8),
          indicatorWeight: 3,
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined, size: 18), text: 'Scanner'),
            Tab(icon: Icon(Icons.compare_arrows, size: 18), text: 'Compare Studio'),
            Tab(icon: Icon(Icons.verified_outlined, size: 18), text: 'Batch & Gaps'),
            Tab(icon: Icon(Icons.assessment_outlined, size: 18), text: 'Audit & Render'),
            Tab(icon: Icon(Icons.terminal, size: 18), text: 'Live Logs'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Sticky Milestone & Activity Bar
          if (activeScan != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: TopMilestoneBanner(
                scan: activeScan,
                onJumpToMatch: () => _tabController.animateTo(1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LiveActivityBar(scan: activeScan),
            ),
          ],

          // Main Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: SCANNER & VIDEO SETUP
                _buildScannerTab(activeScan, scanService, settings, isScanning),

                // TAB 2: SIDE-BY-SIDE COMPARE STUDIO & CANDIDATE BROWSER
                _buildCompareTab(activeScan),

                // TAB 3: 24FPS BATCH VERIFIER, MISSING SCENES & GAPS
                _buildBatchAndGapsTab(activeScan),

                // TAB 4: QUOTA AUDIT, TIMING BREAKDOWN, REPORT & RENDER
                _buildReportAndRenderTab(activeScan),

                // TAB 5: REALTIME STREAMING SYSTEM LOGS
                _buildLogsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab(Scan? scan, ScanService scanService, SettingsService settings, bool isScanning) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Load Videos Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF18181B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.video_collection_outlined, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Load Videos for Matching',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickShortVideo,
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: Text(
                        _shortName != null ? 'Short: $_shortName' : 'Pick Short Video',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _shortName != null ? const Color(0xFF38BDF8) : Colors.white70,
                        side: BorderSide(color: _shortName != null ? const Color(0xFF38BDF8) : Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickMovieVideo,
                      icon: const Icon(Icons.movie_outlined, size: 16),
                      label: Text(
                        _movieName != null ? 'Movie: $_movieName' : 'Pick Full Movie',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _movieName != null ? const Color(0xFF10B981) : Colors.white70,
                        side: BorderSide(color: _movieName != null ? const Color(0xFF10B981) : Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              if (_shortPath != null && _moviePath != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _creatingScan ? null : () => _createNewScan(scanService, settings),
                    icon: _creatingScan
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start Matching Pipeline', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Controls if active scan exists
        if (scan != null) ...[
          // Control Actions Bar (Start / Resume / Stop)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: (!isScanning && scan.status != ScanStatus.done)
                      ? () {
                          scanService.configureGemini(settings.apiKey, model: settings.selectedModel);
                          scanService.startScan();
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Start Scan', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: (!isScanning && scan.chunkCount > 0)
                      ? () {
                          scanService.configureGemini(settings.apiKey, model: settings.selectedModel);
                          scanService.startScan(resume: true);
                        }
                      : null,
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('Resume', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isScanning ? () => scanService.stopScan() : null,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Video Trimmer Panel
          if (scan.movieDuration != null) TrimPanel(scan: scan),

          // Minute Finder & Prescan Windows Panel (Same as web app MinuteFinderPanel)
          MinuteFinderPanel(scan: scan),

          // Minute Approval Step (Same as web app MinuteApproval)
          MinuteApprovalWidget(
            scan: scan,
            onApproved: () {
              scanService.startScan();
            },
          ),

          // TwelveLabs & Pegasus Pre-Filter Panel
          TwelveLabsPanel(scan: scan),

          // Short Video Forensic Coverage Bar (Same as web app computeShortCoverage)
          ShortCoverageWidget(scan: scan),

          // Short Minute & Movie Search Range Selector Panel
          if (scan.shortSegments.isNotEmpty || scan.shortDuration != null) MinuteSelectPanel(scan: scan),

          // Interactive 60s Chunk Timeline
          ChunkTimelineWidget(
            chunks: scan.chunks,
            totalShortMinutes: (scan.shortDuration != null ? (scan.shortDuration! / 60).ceil() : 1),
            onChunkTap: (i) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Chunk #${i + 1}: ${scan.chunks[i].status.name}')),
              );
            },
          ),
          const SizedBox(height: 12),

          // Chunk Results Panel (Raw match lines & details)
          ChunkResultsPanel(scan: scan),

          // Multi-Model & Hardware Safety Board (Same as web app MODEL_POOL)
          ModelBoard(scan: scan),

          // Candidates Panel
          CandidatesPanel(
            scan: scan,
            onSelectMatch: (m) => _tabController.animateTo(1),
          ),
        ],
      ],
    );
  }

  Widget _buildCompareTab(Scan? scan) {
    if (scan == null) {
      return const Center(child: Text('No active scan loaded. Select or start a scan first.'));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Candidate Chooser / Switcher (Same as web app CandidateChooser)
        CandidateChooserWidget(scan: scan),
        // Side by Side Studio
        CompareStudioPanel(scan: scan),
      ],
    );
  }

  Widget _buildBatchAndGapsTab(Scan? scan) {
    if (scan == null) {
      return const Center(child: Text('No active scan loaded. Select or start a scan first.'));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        BatchVerifierPanel(scan: scan),
        // Missing Scene Scanner (Same as web app MissingScenePanel)
        MissingScenePanel(scan: scan),
        GapBackupPanel(scan: scan),
      ],
    );
  }

  Widget _buildReportAndRenderTab(Scan? scan) {
    if (scan == null) {
      return const Center(child: Text('No active scan loaded. Select or start a scan first.'));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Gemini AI Request & Quota Audit (Same as web app ScanUsageReport)
        ScanUsageReportWidget(scan: scan),
        // Task Timing & Execution Duration Report (Same as web app ScanTimingReport)
        ScanTimingReportWidget(scan: scan),
        // Copyright Infringement & Forensic Report
        ReportPanel(scan: scan),
        // Local FFmpeg Proof Video Render
        RenderPanel(scan: scan),
      ],
    );
  }

  Widget _buildLogsTab() {
    return const Padding(
      padding: EdgeInsets.all(14),
      child: LogsPanel(),
    );
  }
}
