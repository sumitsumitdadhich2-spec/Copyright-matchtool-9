import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../services/scan_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../widgets/loading_overlay.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  String? _shortPath;
  String? _shortName;
  int? _shortSize;

  String? _moviePath;
  String? _movieName;
  int? _movieSize;

  String _selectedModel = AppConstants.defaultModel;
  bool _isLoading = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _selectedModel = settings.selectedModel;
  }

  Future<void> _pickShortVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final file = File(result.files.first.path!);
        final size = await file.length();
        setState(() {
          _shortPath = file.path;
          _shortName = result.files.first.name;
          _shortSize = size;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking short video: $e')),
      );
    }
  }

  Future<void> _pickMovieVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final file = File(result.files.first.path!);
        final size = await file.length();
        setState(() {
          _moviePath = file.path;
          _movieName = result.files.first.name;
          _movieSize = size;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking movie video: $e')),
      );
    }
  }

  Future<void> _handleStartScan() async {
    final settings = context.read<SettingsService>();
    if (!settings.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your Gemini API key in Settings first.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ),
      );
      return;
    }

    if (_shortPath == null || _moviePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both Short video and Movie video.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Probing video headers & creating forensic scan...';
    });

    final scanService = context.read<ScanService>();
    scanService.configureGemini(settings.apiKey!, model: _selectedModel);

    try {
      await scanService.createScan(
        shortPath: _shortPath!,
        moviePath: _moviePath!,
        selectedModel: _selectedModel,
      );

      // Start scan asynchronously
      scanService.startScan(autoVerify: settings.autoVerify);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ScanScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize scan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _shortPath != null && _moviePath != null;

    return LoadingOverlay(
      isLoading: _isLoading,
      message: _loadingMessage,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Select Videos for Matching'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Short Video Card
            _buildVideoPickerCard(
              title: '1. Short / Suspect Video',
              subtitle: 'The edited video clip or reel you want to identify',
              icon: Icons.movie_filter_outlined,
              path: _shortPath,
              name: _shortName,
              size: _shortSize,
              color: const Color(0xFF6366F1),
              onPick: _pickShortVideo,
            ),
            const SizedBox(height: 16),

            // Movie Video Card
            _buildVideoPickerCard(
              title: '2. Movie / Source Video',
              subtitle: 'The full movie or long video chunked for forensic comparison (No size limit)',
              icon: Icons.video_collection_outlined,
              path: _moviePath,
              name: _movieName,
              size: _movieSize,
              color: const Color(0xFFF59E0B),
              onPick: _pickMovieVideo,
            ),
            const SizedBox(height: 20),

            // AI Model Configuration
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.psychology_outlined, size: 18, color: Color(0xFF818CF8)),
                      SizedBox(width: 8),
                      Text(
                        'Forensic Model',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedModel,
                    decoration: const InputDecoration(
                      labelText: 'Gemini Model',
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    items: AppConstants.availableModels.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedModel = val);
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '24 fps frame-by-frame analysis with verbatim dialogue quote verification.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Start Button
            ElevatedButton.icon(
              onPressed: canStart ? _handleStartScan : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text('Begin Forensic Match Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPickerCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String? path,
    required String? name,
    required int? size,
    required Color color,
    required VoidCallback onPick,
  }) {
    final isSelected = path != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? color.withOpacity(0.5) : const Color(0xFF2E2E2E),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isSelected) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name ?? path,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          Formatters.formatFileSize(size),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onPick,
                    child: const Text('Change', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Select Video File'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
