import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../services/scan_service.dart';
import '../utils/formatters.dart';

class CompareStudioPanel extends StatefulWidget {
  final Scan scan;

  const CompareStudioPanel({super.key, required this.scan});

  @override
  State<CompareStudioPanel> createState() => _CompareStudioPanelState();
}

class _CompareStudioPanelState extends State<CompareStudioPanel> {
  int _matchIndex = 0;
  VideoPlayerController? _shortController;
  VideoPlayerController? _movieController;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _isRendering = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _initPlayersForMatch();
  }

  @override
  void didUpdateWidget(covariant CompareStudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scan.matches.length != widget.scan.matches.length) {
      _initPlayersForMatch();
    }
  }

  @override
  void dispose() {
    _shortController?.dispose();
    _movieController?.dispose();
    super.dispose();
  }

  ChunkMatch? get _currentMatch {
    if (widget.scan.matches.isEmpty) return null;
    return widget.scan.matches[_matchIndex.clamp(0, widget.scan.matches.length - 1)];
  }

  Future<void> _initPlayersForMatch() async {
    final match = _currentMatch;
    if (match == null || widget.scan.shortPath == null || widget.scan.moviePath == null) return;

    await _shortController?.dispose();
    await _movieController?.dispose();

    try {
      _shortController = VideoPlayerController.file(File(widget.scan.shortPath!));
      _movieController = VideoPlayerController.file(File(widget.scan.moviePath!));

      await Future.wait([
        _shortController!.initialize(),
        _movieController!.initialize(),
      ]);

      // Seek to match start positions
      await _shortController!.seekTo(Duration(milliseconds: (match.shortStart * 1000).toInt()));
      await _movieController!.seekTo(Duration(milliseconds: (match.movieStart * 1000).toInt()));

      _shortController!.setPlaybackSpeed(_playbackSpeed);
      _movieController!.setPlaybackSpeed(_playbackSpeed);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[CompareStudio] Error initializing players: $e');
    }
  }

  void _togglePlayPause() {
    if (_shortController == null || _movieController == null) return;
    setState(() {
      if (_isPlaying) {
        _shortController!.pause();
        _movieController!.pause();
        _isPlaying = false;
      } else {
        _shortController!.play();
        _movieController!.play();
        _isPlaying = true;
      }
    });
  }

  void _stepTime(double deltaSeconds) {
    if (_shortController == null || _movieController == null) return;
    final sPos = _shortController!.value.position;
    final mPos = _movieController!.value.position;

    final newS = sPos + Duration(milliseconds: (deltaSeconds * 1000).toInt());
    final newM = mPos + Duration(milliseconds: (deltaSeconds * 1000).toInt());

    _shortController!.seekTo(newS);
    _movieController!.seekTo(newM);
    setState(() {});
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _shortController?.setPlaybackSpeed(speed);
    _movieController?.setPlaybackSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.scan.matches;
    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.compare, size: 36, color: Colors.white24),
              SizedBox(height: 8),
              Text(
                'No Matches Available for Compare',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 4),
              Text(
                'Matches found during scanning will appear here for side-by-side verification.',
                style: TextStyle(fontSize: 11, color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final match = _currentMatch!;
    final scanService = context.read<ScanService>();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Match Selector & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_arrows, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Match #${_matchIndex + 1} of ${matches.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (match.verified == true ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      match.verified == true ? Icons.verified : Icons.pending_actions,
                      size: 12,
                      color: match.verified == true ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      match.verified == true ? 'AI VERIFIED' : 'RAW MATCH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: match.verified == true ? const Color(0xFF34D399) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Side by Side Video Containers
          Row(
            children: [
              // Left: Short Clip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('SHORT (LEFT)', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _shortController != null && _shortController!.value.isInitialized
                            ? VideoPlayer(_shortController!)
                            : Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.formatDuration(match.shortStart)} - ${Formatters.formatDuration(match.shortEnd)}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right: Movie Clip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('MOVIE (RIGHT)', style: TextStyle(fontSize: 10, color: Colors.cyan, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _movieController != null && _movieController!.value.isInitialized
                            ? VideoPlayer(_movieController!)
                            : Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.formatDuration(match.movieStart)} - ${Formatters.formatDuration(match.movieEnd)}',
                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Playback & Frame-by-Frame Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, size: 20),
                tooltip: '-1 second',
                onPressed: () => _stepTime(-1.0),
              ),
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                tooltip: '-1 frame (1/24s)',
                onPressed: () => _stepTime(-1.0 / 24.0),
              ),
              FloatingActionButton.small(
                onPressed: _togglePlayPause,
                backgroundColor: const Color(0xFF38BDF8),
                child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                tooltip: '+1 frame (1/24s)',
                onPressed: () => _stepTime(1.0 / 24.0),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, size: 20),
                tooltip: '+1 second',
                onPressed: () => _stepTime(1.0),
              ),
            ],
          ),

          // Speed selector & Match navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [0.5, 1.0, 1.5, 2.0].map((s) {
                  final active = _playbackSpeed == s;
                  return InkWell(
                    onTap: () => _setSpeed(s),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF38BDF8) : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.black : Colors.white70,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _matchIndex > 0
                        ? () {
                            setState(() => _matchIndex--);
                            _initPlayersForMatch();
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _matchIndex < matches.length - 1
                        ? () {
                            setState(() => _matchIndex++);
                            _initPlayersForMatch();
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20, color: Colors.white10),

          // Action Buttons: 24fps AI Verification & FFmpeg Local Render
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isVerifying
                      ? null
                      : () async {
                          setState(() => _isVerifying = true);
                          await scanService.verifyMatch(match);
                          if (mounted) setState(() => _isVerifying = false);
                        },
                  icon: _isVerifying
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Verify 24fps AI', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isRendering
                      ? null
                      : () async {
                          setState(() => _isRendering = true);
                          final path = await scanService.renderMatchSideBySide(match);
                          if (mounted) {
                            setState(() => _isRendering = false);
                            if (path != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Rendered proof saved to: $path')),
                              );
                            }
                          }
                        },
                  icon: _isRendering
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.video_library_outlined, size: 16),
                  label: const Text('Render Proof MP4', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
