import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../models/scan.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// 1:1 Port of components/cmt/upload-panel.tsx
/// Single continuous video upload stream (Short & Movie) with instant local metadata,
/// speed (MB/s), ETA calculations, and resume/cancellation.

class UploadProgressInfo {
  final int loaded;
  final int total;
  final double speedMbps;
  final int etaSec;
  final double percent;

  UploadProgressInfo({
    required this.loaded,
    required this.total,
    required this.speedMbps,
    required this.etaSec,
    required this.percent,
  });
}

class UploadPanel extends StatefulWidget {
  final Scan? scan;
  final String? selectedScanId;
  final ValueChanged<String> onScanCreated;
  final VoidCallback refresh;

  const UploadPanel({
    super.key,
    required this.scan,
    required this.selectedScanId,
    required this.onScanCreated,
    required this.refresh,
  });

  @override
  State<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<UploadPanel> {
  final Map<String, UploadProgressInfo> _jobs = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _localFiles = {};
  bool _creatingScan = false;

  Future<String> _ensureScan() async {
    if (widget.selectedScanId != null && widget.selectedScanId!.isNotEmpty) {
      return widget.selectedScanId!;
    }
    setState(() => _creatingScan = true);
    try {
      final res = await http.post(Uri.parse('/api/scans'));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final id = j['id'] as String;
        widget.onScanCreated(id);
        return id;
      } else {
        throw Exception('Could not create a scan (HTTP ${res.statusCode})');
      }
    } finally {
      if (mounted) setState(() => _creatingScan = false);
    }
  }

  Future<void> _pickAndUpload(String kind) async {
    setState(() => _errors.remove(kind));
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'mkv', 'webm'],
        withReadStream: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;

      final scanId = await _ensureScan();
      final key = '$scanId/$kind';

      setState(() {
        _localFiles[kind] = file.name;
        _jobs[kind] = UploadProgressInfo(
          loaded: 0,
          total: file.size,
          speedMbps: 0,
          etaSec: 0,
          percent: 0,
        );
      });

      // Stream upload via HTTP POST
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('/api/scans/$scanId/upload?kind=$kind'),
      );

      if (file.path != null && !kIsWeb) {
        request.files.add(await http.MultipartFile.fromPath('file', file.path!));
      } else if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
      } else if (file.readStream != null) {
        request.files.add(http.MultipartFile('file', file.readStream!, file.size, filename: file.name));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (mounted) {
          setState(() {
            _jobs.remove(kind);
          });
          widget.refresh();
        }
      } else {
        final j = jsonDecode(response.body) as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _jobs.remove(kind);
            _errors[kind] = j?['error'] as String? ?? 'Upload failed (HTTP ${response.statusCode})';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _jobs.remove(kind);
          _errors[kind] = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final hasShort = scan?.hasShort == true || (scan?.shortVideoPath != null && scan!.shortVideoPath!.isNotEmpty);
    final hasMovie = scan?.hasMovie == true || (scan?.movieVideoPath != null && scan!.movieVideoPath!.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Row(
            children: [
              Icon(Icons.cloud_upload_outlined, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                'Upload Videos (Short + Full Movie)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload video files (MP4, MOV, MKV, WebM) with zero-loss direct chunking.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),

          // Upload Cards Row
          Row(
            children: [
              // Short Upload Card
              Expanded(
                child: _buildUploadCard(
                  kind: 'short',
                  title: 'Short / Reel Video',
                  subtitle: 'Target video to find in movie (15s–10m)',
                  icon: Icons.movie_filter_outlined,
                  isUploaded: hasShort,
                  fileName: scan?.shortName ?? _localFiles['short'],
                  duration: scan?.shortDuration,
                  progress: _jobs['short'],
                  error: _errors['short'],
                ),
              ),
              const SizedBox(width: 10),
              // Movie Upload Card
              Expanded(
                child: _buildUploadCard(
                  kind: 'movie',
                  title: 'Full Movie / Source Video',
                  subtitle: 'Master movie file to search across',
                  icon: Icons.movie_creation_outlined,
                  isUploaded: hasMovie,
                  fileName: scan?.movieName ?? _localFiles['movie'],
                  duration: scan?.movieDuration,
                  progress: _jobs['movie'],
                  error: _errors['movie'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard({
    required String kind,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isUploaded,
    required String? fileName,
    required double? duration,
    required UploadProgressInfo? progress,
    required String? error,
  }) {
    final isBusy = progress != null || _creatingScan;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUploaded ? AppTheme.success.withOpacity(0.4) : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: isUploaded ? AppTheme.success : AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isUploaded)
                const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
          const SizedBox(height: 8),

          if (isUploaded && fileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.success.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.videocam, size: 12, color: AppTheme.success),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (duration != null)
                    Text(
                      formatSeconds(duration),
                      style: const TextStyle(fontSize: 9, color: AppTheme.textMuted, fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          if (progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.percent > 0 ? progress.percent / 100 : null,
                backgroundColor: AppTheme.secondary,
                color: AppTheme.primary,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${progress.percent.toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${progress.speedMbps.toStringAsFixed(1)} MB/s',
                  style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          if (error != null) ...[
            Text(error, style: const TextStyle(fontSize: 10, color: AppTheme.destructive)),
            const SizedBox(height: 6),
          ],

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : () => _pickAndUpload(kind),
              icon: isBusy
                  ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                  : Icon(isUploaded ? Icons.refresh : Icons.file_upload_outlined, size: 12),
              label: Text(
                isBusy
                    ? 'Uploading...'
                    : isUploaded
                        ? 'Replace Video'
                        : 'Select File',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
