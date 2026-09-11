import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../services/settings_service.dart';
import '../utils/formatters.dart';

class MinuteFinderPanel extends StatefulWidget {
  final Scan scan;

  const MinuteFinderPanel({super.key, required this.scan});

  @override
  State<MinuteFinderPanel> createState() => _MinuteFinderPanelState();
}

class _MinuteFinderPanelState extends State<MinuteFinderPanel> {
  String _mode = 'gemini'; // 'gemini' | 'twelvelabs' | 'off'

  final List<Map<String, String>> _steps = [
    {'key': 'preparing', 'label': 'Preparing Video'},
    {'key': 'uploading', 'label': 'Key Uploads'},
    {'key': 'scanning', 'label': '20m Windows'},
    {'key': 'backup', 'label': 'Backup Gaps'},
    {'key': 'starting_scan', 'label': 'Chunk Scan'},
  ];

  int _getStepIndex(String status) {
    switch (status) {
      case 'preparing':
        return 0;
      case 'uploading':
        return 1;
      case 'scanning':
        return 2;
      case 'backup':
        return 3;
      case 'starting_scan':
      case 'done':
        return 4;
      default:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanService = context.watch<ScanService>();
    final settings = context.watch<SettingsService>();
    final scan = widget.scan;
    final prescanStatus = scan.prescanStatus;
    final isRunning = scanService.isScanning && (prescanStatus != 'idle' && prescanStatus != 'done');
    final currentStepIdx = _getStepIndex(prescanStatus);

    final windows = scan.prescanWindows;
    final matchWindows = windows.where((w) => w.status == 'match').length;
    final doneWindows = windows.where((w) => w.status == 'match' || w.status == 'no_match').length;
    final failedWindows = windows.where((w) => w.status == 'error').length;
    final keyCount = settings.hasApiKey ? 1 : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Auto Pipeline — Minute Finder',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isRunning
                      ? const Color(0xFF38BDF8).withOpacity(0.2)
                      : (prescanStatus == 'done'
                          ? const Color(0xFF10B981).withOpacity(0.2)
                          : Colors.white10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isRunning
                      ? 'RUNNING...'
                      : (prescanStatus == 'done' ? 'CHUNK SCAN STARTED' : 'READY'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isRunning
                        ? const Color(0xFF38BDF8)
                        : (prescanStatus == 'done' ? const Color(0xFF34D399) : Colors.white60),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Gemini Files API Upload per Key ➔ 20-min Window Scan ➔ Backup Gap Pass ➔ Auto-Launch 24fps Chunk Scan.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),

          // Mode Selector
          Row(
            children: [
              ChoiceChip(
                label: const Text('Gemini Minute Finder', style: TextStyle(fontSize: 11)),
                selected: _mode == 'gemini',
                onSelected: (_) => setState(() => _mode = 'gemini'),
                selectedColor: const Color(0xFF38BDF8).withOpacity(0.2),
                checkmarkColor: const Color(0xFF38BDF8),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('TwelveLabs', style: TextStyle(fontSize: 11)),
                selected: _mode == 'twelvelabs',
                onSelected: (_) => setState(() => _mode = 'twelvelabs'),
                selectedColor: const Color(0xFF818CF8).withOpacity(0.2),
                checkmarkColor: const Color(0xFF818CF8),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Off (Full Scan)', style: TextStyle(fontSize: 11)),
                selected: _mode == 'off',
                onSelected: (_) => setState(() => _mode = 'off'),
                selectedColor: Colors.white12,
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_mode == 'gemini') ...[
            // Actions Toolbar
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ElevatedButton.icon(
                  onPressed: isRunning
                      ? null
                      : () {
                          scanService.configureGemini(settings.apiKey, model: settings.selectedModel);
                          scanService.runGeminiMinuteFinder();
                        },
                  icon: isRunning
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Start Minute Finder', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                if (failedWindows > 0)
                  OutlinedButton.icon(
                    onPressed: isRunning ? null : () => scanService.retryFailedWindows(),
                    icon: const Icon(Icons.replay, size: 14),
                    label: Text('Retry Failed ($failedWindows)', style: const TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                if (windows.isNotEmpty && !isRunning)
                  OutlinedButton.icon(
                    onPressed: () => scanService.rerunMinuteFinder(),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Re-run', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                if (isRunning)
                  OutlinedButton.icon(
                    onPressed: () => scanService.stopMinuteFinder(),
                    icon: const Icon(Icons.stop, size: 14, color: Color(0xFFEF4444)),
                    label: const Text('Stop', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Pipeline Step Badges
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_steps.length, (i) {
                  final s = _steps[i];
                  final isPast = currentStepIdx > i || prescanStatus == 'done';
                  final isCurrent = currentStepIdx == i && isRunning;

                  Color bg = Colors.white.withOpacity(0.04);
                  Color textCol = Colors.white54;
                  Color border = Colors.white12;

                  if (isPast) {
                    bg = const Color(0xFF10B981).withOpacity(0.15);
                    textCol = const Color(0xFF34D399);
                    border = const Color(0xFF10B981).withOpacity(0.3);
                  } else if (isCurrent) {
                    bg = const Color(0xFF38BDF8).withOpacity(0.15);
                    textCol = const Color(0xFF38BDF8);
                    border = const Color(0xFF38BDF8);
                  }

                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPast)
                          const Icon(Icons.check, size: 12, color: Color(0xFF10B981))
                        else if (isCurrent)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF38BDF8)),
                          )
                        else
                          Text('${i + 1}.', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                        const SizedBox(width: 4),
                        Text(
                          s['label']!,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textCol),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 12),

            // STEP 1 DETAILS: Key Uploads Status
            if (scan.prescanUploads.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Gemini Files API Upload: ${scan.prescanUploads.first.keyId} (${scan.prescanUploads.first.status.toUpperCase()})',
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70),
                      ),
                    ),
                    if (scan.prescanUploads.first.status == 'ready')
                      const Text('✓ Ready for 47h', style: TextStyle(fontSize: 9, color: Color(0xFF10B981))),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // STEP 2 DETAILS: 20-min Windows Breakdown Grid
            if (windows.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '20-Minute Windows ($doneWindows/${windows.length} done • $matchWindows matches)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: windows.map((w) {
                  Color bg = const Color(0xFF27272A);
                  Color border = Colors.white10;
                  Widget? statusIcon;

                  if (w.status == 'match') {
                    bg = const Color(0xFF10B981).withOpacity(0.2);
                    border = const Color(0xFF10B981);
                    statusIcon = const Icon(Icons.check, size: 12, color: Color(0xFF10B981));
                  } else if (w.status == 'scanning') {
                    bg = const Color(0xFF38BDF8).withOpacity(0.2);
                    border = const Color(0xFF38BDF8);
                    statusIcon = const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF38BDF8)),
                    );
                  } else if (w.status == 'no_match') {
                    bg = Colors.black38;
                  } else if (w.status == 'error') {
                    bg = const Color(0xFFEF4444).withOpacity(0.2);
                    border = const Color(0xFFEF4444);
                  }

                  return Tooltip(
                    message: 'Window #${w.index + 1}: ${Formatters.formatDuration(w.startSec)} - ${Formatters.formatDuration(w.endSec)} (${w.status})',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (statusIcon != null) ...[
                            statusIcon,
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'W${w.index + 1} (${(w.startSec / 60).toInt()}m-${(w.endSec / 60).toInt()}m)',
                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          ),
                          if (w.matchedMinutes.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '+${w.matchedMinutes.length}',
                                style: const TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],

            // STEP 3 DETAILS: Backup Pass Info
            if (scan.backupState.status != 'idle') ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_moon_outlined, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Backup Gap Pass: ${scan.backupState.status.toUpperCase()} (${scan.backupState.gapCount} gaps checked • ${scan.backupState.recoveredMinutes.length} recovered)',
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
