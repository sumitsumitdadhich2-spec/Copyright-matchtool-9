import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/formatters.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  final double? initialPosition;
  final double? targetEnd;
  final bool autoPlay;
  final bool loop;
  final String? title;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
    this.initialPosition,
    this.targetEnd,
    this.autoPlay = false,
    this.loop = false,
    this.title,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _controller?.dispose();
      _initPlayer();
    } else if (oldWidget.initialPosition != widget.initialPosition && widget.initialPosition != null) {
      _controller?.seekTo(Duration(milliseconds: (widget.initialPosition! * 1000).toInt()));
    }
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() {
          _hasError = true;
          _errorMessage = 'File not found on device';
        });
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      _controller!.setLooping(widget.loop);

      if (widget.initialPosition != null && widget.initialPosition! > 0) {
        await _controller!.seekTo(
          Duration(milliseconds: (widget.initialPosition! * 1000).toInt()),
        );
      }

      if (widget.autoPlay) {
        await _controller!.play();
      }

      _controller!.addListener(_onControllerUpdate);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _onControllerUpdate() {
    if (widget.targetEnd != null && _controller != null) {
      final currentSec = _controller!.value.position.inMilliseconds / 1000.0;
      if (currentSec >= widget.targetEnd!) {
        _controller!.pause();
        if (widget.initialPosition != null) {
          _controller!.seekTo(Duration(milliseconds: (widget.initialPosition! * 1000).toInt()));
        }
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Video playback error',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _initPlayer,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final posSec = _controller!.value.position.inMilliseconds / 1000.0;
    final durSec = _controller!.value.duration.inMilliseconds / 1000.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF1A1A1A),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio > 0
                ? _controller!.value.aspectRatio
                : 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                GestureDetector(
                  onTap: () {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _controller!.value.isPlaying ? 0.0 : 0.85,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF161616),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                  onPressed: () {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                ),
                Text(
                  Formatters.formatTimeShort(posSec),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: posSec.clamp(0.0, durSec > 0 ? durSec : 1.0),
                      min: 0.0,
                      max: durSec > 0 ? durSec : 1.0,
                      activeColor: const Color(0xFF6366F1),
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        _controller!.seekTo(Duration(milliseconds: (val * 1000).toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  Formatters.formatTimeShort(durSec),
                  style: const TextStyle(fontSize: 11, color: Colors.white60, fontFamily: 'monospace'),
                ),
                if (widget.initialPosition != null)
                  IconButton(
                    icon: const Icon(Icons.replay, size: 18),
                    tooltip: 'Jump to segment start',
                    onPressed: () {
                      _controller!.seekTo(
                        Duration(milliseconds: (widget.initialPosition! * 1000).toInt()),
                      );
                      _controller!.play();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
