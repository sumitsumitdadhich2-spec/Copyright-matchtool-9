import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiKeyController;
  bool _obscureKey = true;
  bool _isSaving = false;
  int _storageUsed = 0;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _apiKeyController = TextEditingController(text: settings.apiKey ?? '');
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    final storage = context.read<StorageService>();
    final bytes = await storage.getTotalStorageUsed();
    if (mounted) setState(() => _storageUsed = bytes);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    final settings = context.read<SettingsService>();
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      await settings.clearApiKey();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API Key cleared')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    await settings.setApiKey(key);
    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API Key saved securely.'),
          backgroundColor: Color(0xFF22C55E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Gemini API Key
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
                    Icon(Icons.key, color: Color(0xFFF59E0B), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Google Gemini API Key',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your personal API key from Google AI Studio. It stays on this phone and is never shared.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    hintText: 'AIzaSy...',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureKey ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white60,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        ),
                        if (_apiKeyController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white60, size: 20),
                            onPressed: () {
                              _apiKeyController.clear();
                              _saveApiKey();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveApiKey,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save API Key'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 2: Model & Forensic Options
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
                  'Model & Processing Preferences',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: settings.selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'Default Gemini Model',
                  ),
                  items: AppConstants.availableModels.map((m) {
                    return DropdownMenuItem(value: m, child: Text(m));
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
                    'Automatically run forensic verifier on all candidate matches',
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
                  'To prevent overheating, thermal throttling, and process termination on high-core Android devices (8+ cores), local FFmpeg processing is strictly capped at a maximum of 5 worker threads.',
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
                      Text('Max Allowed CPU Threads:', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      Text('5 Cores (Hard Limit)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF22C55E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 4: Local Storage
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('App Cache & Chunks', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      'Total storage used: ${Formatters.formatFileSize(_storageUsed)}',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: _storageUsed > 0
                      ? () async {
                          final storage = context.read<StorageService>();
                          for (final scan in storage.savedScans) {
                            await storage.cleanChunks(scan.id);
                          }
                          await _loadStorageInfo();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Temporary video chunks cleared.')),
                            );
                          }
                        }
                      : null,
                  child: const Text('Clean Chunks', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
