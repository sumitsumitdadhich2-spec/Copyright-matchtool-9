import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../utils/models.dart';
import '../widgets/api_key_manager_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _storageUsed = 0;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    final storage = context.read<StorageService>();
    final bytes = await storage.getTotalStorageUsed();
    if (mounted) setState(() => _storageUsed = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & API Key Pool'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: 20-Key Pool & TwelveLabs Manager (Exact Web App Parity)
          const ApiKeyManagerWidget(),
          const SizedBox(height: 16),

          // Section 2: Model & Forensic Options (Exactly matching web app)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Model Architecture (Same as Web App)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chunk mapping is locked to high-precision models. 24fps verification automatically runs on high-throughput 500 RPD lite models.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: AppConstants.availableModels.contains(settings.selectedModel)
                      ? settings.selectedModel
                      : AppConstants.defaultModel,
                  decoration: const InputDecoration(
                    labelText: 'Chunk Mapping Model',
                  ),
                  items: AppModels.allModels.map((m) {
                    return DropdownMenuItem(
                      value: m.id,
                      child: Text('${m.id} (${m.role})', style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) settings.setSelectedModel(val);
                  },
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-verify matches', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Automatically run 24fps frame verifier (gemini-3.5-flash-lite) on candidate matches',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  value: settings.autoVerify,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (val) => settings.setAutoVerify(val),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep chunk files after scan', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Save 1-minute .mp4 chunks on device storage for instant review',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  value: settings.keepChunks,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (val) => settings.setKeepChunks(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 3: Hardware Protection Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.memory, color: Color(0xFF22C55E), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'CPU & Thermal Protection',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'To prevent overheating, thermal throttling, and system kills on mobile devices, local FFmpeg processing is capped at a maximum of 5 CPU cores.',
                  style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max FFmpeg Threads', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      Text('5 Threads', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF22C55E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 4: Local Storage Cache
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder, color: Color(0xFF6366F1), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Local Storage Cache',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Used for temporary chunks & frames:', style: TextStyle(fontSize: 12, color: Colors.white60)),
                    Text(
                      Formatters.formatBytes(_storageUsed),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    final storage = context.read<StorageService>();
                    await storage.cleanupAll();
                    await _loadStorageInfo();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Storage cache cleared successfully')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear Temporary Cache'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
