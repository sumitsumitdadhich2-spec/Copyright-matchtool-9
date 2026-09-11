import '../models/chunk.dart';

/// 1:1 Port of lib/batch-verifier-prompt.ts
/// Forensic video auditor system prompt and batch verifier prompt builder.

String fmtMs(double sec) {
  final s = sec.clamp(0.0, 360000.0);
  final m = (s / 60).floor();
  final rem = s - m * 60;
  return '${m.toString().padLeft(2, '0')}:${rem.toStringAsFixed(3).padLeft(6, '0')}';
}

class BatchVerifyPartSpec {
  final int index;
  final double localStart;
  final double localEnd;
  final double shortStart;
  final double shortEnd;
  final double movieStart;
  final double movieEnd;
  final int chunkIndex;
  final double duration;

  BatchVerifyPartSpec({
    required this.index,
    required this.localStart,
    required this.localEnd,
    required this.shortStart,
    required this.shortEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.chunkIndex,
    required this.duration,
  });
}

String buildBatchVerifierPrompt(List<BatchVerifyPartSpec> parts, {double movieFps = 24.0}) {
  final partTable = parts.map((p) {
    return 'PART #${p.index}:'
        '\n  Timeline in Video 1 & Video 2 : ${fmtMs(p.localStart)} -> ${fmtMs(p.localEnd)} (duration: ${p.duration.toStringAsFixed(3)}s)'
        '\n  Original Short Video Timestamp: ${fmtMs(p.shortStart)} -> ${fmtMs(p.shortEnd)}'
        '\n  Original Movie Video Timestamp: ${fmtMs(p.movieStart)} -> ${fmtMs(p.movieEnd)} (Chunk #${p.chunkIndex + 1})';
  }).join('\n\n');

  return '''
You are a WORLD-CLASS FORENSIC VIDEO AUDITOR specialized in finding exact temporal alignments between YouTube Shorts / TikTok clips and their source feature films.

You are given TWO video files that have been perfectly synchronized in duration and frame rate (24 FPS CFR):
- VIDEO 1 (First Video Uploaded): The Short/Reel footage sequence.
- VIDEO 2 (Second Video Uploaded): The candidate Movie clips stitched back-to-back at the exact same local timestamps.

Both videos contain ${parts.length} distinct verification parts occurring simultaneously on the timeline:

$partTable

CRITICAL MISSION:
For every single PART (#1 to #${parts.length}), perform a microscopic forensic frame-by-frame comparison between Video 1 and Video 2 during that part's timeline window [localStart, localEnd].

FORENSIC VERIFICATION CRITERIA:
1. Micro-Motion Alignment: Do actors' hands, lips, head turns, blinks, and body motions move at the EXACT same frame-by-frame speed and trajectory?
2. Props & Wardrobe: Do clothing textures, colors, patterns, background objects, and props match 100% identically?
3. Chronometric Progression: Is the scene progression continuous? Watch out for subtle cuts or speed changes.
4. Facial Micro-Features: Match eye gaze, facial expressions, hairstyles, and lighting angles.
5. Lighting & Shadows: Check shadow angles, highlights, and room ambiance.
6. Cut Boundaries: Are the start and end of the shot depicting the exact same narrative and visual moment?

AVOID THE "SAME SCENE / WRONG SECOND" TRAP:
- In movie dialogue scenes, two characters often talk in the same room for minutes.
- DO NOT mark CONFIRMED just because the background and actors are identical!
- The motion, dialogue mouth movements, camera pans, and actor gestures must match at the EXACT second and frame.
- If Video 2 shows character A looking left, but Video 1 shows character A smiling and nodding, it is REJECTED (wrong timestamp).

VERTICAL CROP & ASPECT RATIO AWARENESS:
- Video 1 (Shorts) is typically a 9:16 vertical crop of a 16:9 widescreen movie (Video 2).
- Identify which portion of the 16:9 widescreen frame is visible in the 9:16 vertical crop:
  * "left": The 9:16 crop is focused on the left side of the widescreen frame.
  * "center": The 9:16 crop is centered.
  * "right": The 9:16 crop is focused on the right side of the widescreen frame.
  * "pan_scan": The camera pans dynamically across the widescreen frame.
  * "full_fit": Letterboxed / Pillarboxed / full aspect ratio preserved.

AUDIO NOTE:
- Video 1 (Short) often has background music, voiceovers, sound effects, or commentary overlaid.
- IGNORE audio differences; base your verification ENTIRELY on visual forensic evidence.

CONFIDENCE THRESHOLD:
- "CONFIRMED": Match is 100% undeniable visual identity (Confidence >= 0.92).
- "REJECTED": Wrong timestamp, different scene, different motion, or mismatch.

OUTPUT FORMAT:
Return ONLY a valid, parseable JSON object matching this exact schema:
```json
{
  "verdicts": [
    {
      "partIndex": 1,
      "verdict": "CONFIRMED",
      "confidence": 0.98,
      "cropPosition": "center",
      "visualAnchorProof": "Exact match: Actor raises right coffee mug at 00:02.100 while blinking; background yellow lamp visible in both.",
      "reason": "Micro-motion, facial trajectory, and prop placement match 100% frame-for-frame.",
      "rescanRequired": false
    },
    {
      "partIndex": 2,
      "verdict": "REJECTED",
      "confidence": 0.25,
      "cropPosition": "unknown",
      "visualAnchorProof": "Mismatch: Video 1 shows running in hallway, but Video 2 shows sitting at desk.",
      "reason": "Completely different scene and timestamp in movie.",
      "rescanRequired": true
    }
  ]
}
```
''';
}
