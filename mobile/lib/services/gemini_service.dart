import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/chunk.dart';
import '../utils/constants.dart';

enum GeminiErrorKind {
  invalidKey,
  rateLimited,
  quotaExhausted,
  policyBlocked,
  unavailable,
  empty,
  network,
  other,
}

class GeminiException implements Exception {
  final GeminiErrorKind kind;
  final String message;
  GeminiException(this.kind, this.message);

  @override
  String toString() => 'GeminiException($kind): $message';
}

class ChunkMapResult {
  final String rawText;
  final List<ChunkMatch> matches;
  final String? warning;
  final int? tokensUsed;

  ChunkMapResult({
    required this.rawText,
    required this.matches,
    this.warning,
    this.tokensUsed,
  });
}

class VerifyResult {
  final bool same;
  final String reason;
  final String rawText;

  VerifyResult({
    required this.same,
    required this.reason,
    required this.rawText,
  });
}

class GeminiService {
  GenerativeModel? _model;
  String? _apiKey;
  String _selectedModel = AppConstants.defaultModel;

  // Exact forensic prompt copied verbatim from web app's lib/gemini.ts
  static const String CHUNK_MAP_PROMPT = '''You are a forensic video analyst. You are given TWO videos:
- Video 1: a SHORT VIDEO that was edited together from clips of a movie.
- Video 2: a ONE-MINUTE CHUNK cut from the original movie.

Both videos are exactly 24 fps. Analyze them frame by frame at 24 fps precision.

Respond in Hinglish (Hindi written in Latin script). Spoken dialogue must always be QUOTED VERBATIM in its original language.

Your answer has exactly TWO parts:

=====================
HISSA 1 — SHORT VIDEO TIME MAP
=====================
Watch Video 1 from start to finish and break it into small, fine-grained segments:
- Har segment chhota hona chahiye — zyada tar segments 1 second ya usse kam ke hone chahiye. Ek lambi continuous shot ko bhi chhote sub-segments me todo taaki mapping precise rahe.
- Segments contiguous hone chahiye: har segment ka start = pichle segment ka end. Pehla segment 00:00.000 se shuru ho, aakhri segment video ki total duration par khatam ho. Koi gap nahi, koi overlap nahi.
- Har line ka format:
  mm:ss.mmm - mm:ss.mmm (startFrame-endFrame frames): <SHORT description, max 10-12 words — kaun kya kar raha hai; agar koi bolta hai to sirf exact quoted words>
- Description LAMBA MAT karo — output token budget limited hai. Sirf identify karne layak minimum detail + exact dialogue quote.
- Frame numbers = timestamp x 24 (24 fps). Timestamps millisecond precision me, frame boundaries 1/24s (0.0417s) steps par aligned.
- Dialogue sabse strong fingerprint hai — kabhi summarize mat karo, hamesha exact words quote karo.

=====================
HISSA 2 — MOVIE MAP TIME
=====================
Ab HISSA 1 ke HAR EK segment ke liye Video 2 (movie chunk) me EXACT wahi footage dhundho (same recording, frame for frame — sirf similar scene nahi).

STRICT RULES:
1. 1:1 SAME-DURATION MAPPING (sabse important rule): Har short segment ka movie me matched window EXACTLY utni hi duration ka hona chahiye. Agar short segment 0.417s ka hai, to movie window bhi 0.417s ka hoga — na kam, na zyada. (movie_end - movie_start) MUST equal (short_end - short_start). Kabhi bhi ek chhote short segment ko movie ke bade 5-10 second block par map mat karo.
2. HAR SEGMENT KI APNI LINE: Har short segment ke liye alag mapping line likho. Kai segments ko ek saath ek badi range me merge mat karo (consecutive NOT FOUND segments ko ek line me group karna allowed hai).
3. Movie timestamps Video 2 ki APNI clock se aane chahiye (00:00.000 se ~01:00.000) — frames ko actually dekh kar. Short video ke timestamps copy karke movie column me daalna FORBIDDEN hai jab tak tumne wahi frames Video 2 me us position par khud verify na kiye hon.
4. NO EXTRAPOLATION (CRITICAL): Ek baar offset mil jane ke baad "short_time + offset" formula se aage ke segments AUTOMATICALLY map karna STRICTLY FORBIDDEN hai. Ye sabse common galti hai. Har naye segment ke liye Video 2 ke actual frames FIR SE dekho aur independently verify karo. Agar tum notice karo ki tumhare consecutive mappings ek fixed offset follow kar rahe hain (e.g. har match exactly +3.000s par), to RUK JAO aur har ek ko dobara verify karo — ye extrapolation drift ka signal hai, real matching ka nahi.
5. DIALOGUE AUDIO VERIFICATION: Agar short segment me koi dialogue hai, to matched movie window me WAHI EXACT dialogue Video 2 ke audio me us position par actually SUNAI dena chahiye. Agar us movie window me wo words sunai nahi dete, to match INVALID hai — NOT FOUND likho. Bina dialogue verify kiye dialogue-wale segment ko map karna FORBIDDEN hai.
6. CHUNK KA END = FOOTAGE KA END: Ye chunk poori movie ka sirf ek 1-minute tukda hai. Short video ka content is chunk ke END par cut ho sakta hai — uske baad ke short segments AGLE chunk me hain, is chunk me NAHI. Agar tumhara matched footage Video 2 ke end ke paas khatam ho raha hai, to baaki bache short segments ko zabardasti aakhri seconds me squeeze mat karo — unhe NOT FOUND likho. Suspicious sign: agar tumhara last match exactly Video 2 ke end (~01:00.000) par khatam hota hai, to bahut dhyan se verify karo.
7. NOT FOUND: Agar koi short segment is movie chunk ke andar NAHI milta, to clearly likho "NOT FOUND — ye scene is movie chunk ke andar nahi hai". Bahut se segments milenge hi nahi — ye NORMAL aur EXPECTED hai. Zabardasti match banana false positive hai, jo miss karne se bahut zyada bura hai. SIMILAR IS NOT SAME — same actors/location par different moment = NOT FOUND. Ek naya scene short me shuru hua hai iska matlab ye NAHI ki wo is chunk me continue hota hai.
8. Movie ke andar segments ka order short video ke order se alag ho sakta hai (short video edited hai) — har segment independently dhundho.
9. FINAL SELF-CHECK: Answer dene se pehle apne saare matches dobara scan karo. Jo bhi match sirf "pichle match ke baad aata hai isliye" bana hai (frame evidence ke bina), use NOT FOUND me badlo.

Har matched line ka format:
  Short mm:ss.mmm - mm:ss.mmm --> Movie mm:ss.mmm - mm:ss.mmm (startFrame-endFrame frames)

Na milne par:
  Short mm:ss.mmm - mm:ss.mmm --> NOT FOUND — <chhota reason>

Poore answer me sirf HISSA 1 aur HISSA 2 do, aur kuch nahi.''';

  // Verifier prompt copied verbatim from web app's lib/gemini.ts
  static const String VERIFY_PROMPT = '''You are a forensic video verifier. You are given TWO very short clips. Both are exactly 24 fps — compare them frame by frame at 24 fps precision.

- Video 1: ek segment jo ek SHORT VIDEO se kata gaya hai.
- Video 2: ek segment jo ek MOVIE se kata gaya hai.

SAWAL: Kya ye dono clips EXACT SAME footage hain — same recording, same moment, frame-for-frame?

Respond in Hinglish (Hindi written in Latin script). Dialogue hamesha VERBATIM quote karo, original language me.

Tumhara answer TEEN parts me hoga. Pehle EVIDENCE, phir COMPARE, phir VERDICT. Bina evidence likhe seedha verdict dena FORBIDDEN hai — yahi sabse badi galti hai jo false results deti hai.

=====================
STEP 1 — EVIDENCE (dono clips ko alag-alag dhyan se dekho)
=====================
CLIP 1 ke liye 2-4 short lines likho:
- Kya action ho raha hai (kaun kya karta hai, kis order me)
- Agar koi bolta hai: EXACT quoted words
- Shot/camera: close-up ya wide, camera static ya moving, koi cut hai to kahan
CLIP 2 ke liye bhi EXACTLY yahi 2-4 lines likho, independently — Clip 1 ki lines copy karke mat likho.

=====================
STEP 2 — COMPARE (point by point)
=====================
In anchors par dono clips ko compare karo, har ek ke aage MATCH / MISMATCH / N.A. likho:
- DIALOGUE: exact words + voice same? (sabse strong fingerprint — words alag = DIFFERENT, pakka. LEKIN: agar kisi clip me audio mute hai, music se dab gaya hai, ya words clearly sunai NAHI dete — to MISMATCH mat likho, N.A. likho aur ACTION/SHOT par judge karo)
- ACTION: same movements, same order, same timing?
- SHOT: same framing, same camera angle, same cuts on same beats? (crop/zoom ki wajah se framing tight/loose dikhna MISMATCH nahi hai — sirf ALAG camera angle/alag shot MISMATCH hai)
- BACKGROUND/DETAILS: same background elements, props, costume, lighting continuity?

=====================
STEP 3 — VERDICT (rules apply karo)
=====================
RULES:
1. SAME ka matlab: same RECORDING, same MOMENT — sirf same scene nahi. Visuals AUR audio dono se confirm karo.
2. SIMILAR IS NOT SAME: same actors, same location, same costume — lekin different take ya different moment (alag action, alag words, alag shot) = DIFFERENT.
3. QUALITY DIFFERENCE IS NOT DIFFERENT: crop, resize, zoom, letterbox/black bars, aspect-ratio change, compression artifacts, blur, color-grade, brightness, saturation/BW filter, watermark, text-overlay, subtitles, audio quality/background music added, original audio replaced ya muted, frame-rate wobble, duplicate/dropped frames, mirrored/flipped image — ye sab IGNORE karo. Underlying footage same ho to VERDICT SAME hi hoga, chahe quality kitni bhi alag ho. In cheezon ko DIFFERENT ka reason banana FORBIDDEN hai.
4. BOUNDARY TOLERANCE: dono clips ke start/end par misalignment ho sakta hai (ek clip doosri se ~0.5-1s aage/piche shifted, ya ek clip me thoda extra footage aage/piche). Sirf OVERLAPPING hisse ko judge karo. Agar overlap frame-for-frame same footage hai, to VERDICT SAME — "Clip 2 me shuru/end me extra frames hain" DIFFERENT ka reason NAHI hai.
5. DIFFERENT ke liye CONCRETE EVIDENCE zaroori hai: DIFFERENT sirf tab bolo jab tum kam se kam EK concrete, nameable difference de sako jo Step 2 ke kisi MISMATCH se aata ho (e.g. "dialogue words alag: 'X' vs 'Y'", "Clip 1 me wo uthta hai, Clip 2 me baitha rehta hai", "bilkul alag scene"). Vague feeling ("lag raha hai alag hai", "timing thodi off lagti hai") valid reason NAHI hai.
6. SAME ke liye bhi POSITIVE EVIDENCE zaroori hai: SAME sirf tab bolo jab Step 2 me DIALOGUE ya ACTION me se kam se kam ek clear MATCH ho + koi real MISMATCH na ho. "Koi difference nahi dikha" akela kaafi nahi hai agar tumne clips theek se dekhi hi nahi.
7. SPEED/PLAYBACK TOLERANCE: short video me footage thoda speed-up/slow-down, re-encoded, ya duplicate/dropped frames wala ho sakta hai. Isse action ki timing me chhota sa antar (~10-15%) aa sakta hai — ye DIFFERENT ka reason NAHI hai jab tak actions ka ORDER aur CONTENT same hai.
8. DECISION PROCEDURE (isi order me socho, yahi final hai):
   a) Step 2 me koi CONCRETE MISMATCH hai jo overlapping target window ke ANDAR hai (dialogue words alag, action alag, bilkul alag moment/scene)? → DIFFERENT.
   b) Koi mismatch nahi + DIALOGUE ya ACTION me kam se kam ek clear MATCH? → SAME.
   c) Poore Step 2 ke baad bhi tum EK BHI concrete, nameable mismatch NAHI likh paye? → verdict SAME hai. "Pakka nahi hun", "thoda alag lag raha hai", "quality kharab hai isliye confirm nahi kar sakta" jaise vague doubts DIFFERENT ka reason NAHI hain — DIFFERENT SIRF concrete evidence par milta hai. Ek SAHI match ko galti se DIFFERENT bolna utna hi bura hai jitna galat match ko SAME bolna.
9. SELF-CHECK: Verdict likhne se pehle apne Step 1 ke notes dobara padho. Kya tumhara verdict tumhare khud ke likhe evidence se consistent hai? Agar Step 2 me sab MATCH/N.A. hai lekin tum DIFFERENT likh rahe ho (ya koi real MISMATCH hai aur tum SAME likh rahe ho), to verdict galat hai — use theek karo. Ye bhi check karo ki tumhara har MISMATCH target window ke ANDAR ka hai — padding/boundary area ka mismatch count NAHI hota.

Answer ke END me EXACTLY ye do lines do (yahi format, aur kuch nahi in lines me):
VERDICT: SAME
ya
VERDICT: DIFFERENT
REASON: <ek chhoti line Hinglish me — Step 2 ke concrete evidence ke saath>''';

  bool get isConfigured => _apiKey != null && _apiKey!.trim().isNotEmpty;

  void configure(String apiKey, {String? modelName}) {
    _apiKey = apiKey.trim();
    if (modelName != null && modelName.isNotEmpty) {
      _selectedModel = modelName;
    }
    _model = GenerativeModel(
      model: _selectedModel,
      apiKey: _apiKey!,
      generationConfig: GenerationConfig(
        temperature: 0,
        maxOutputTokens: 8192,
      ),
    );
  }

  /// Run chunk mapping request comparing short video and 1-minute movie chunk
  Future<ChunkMapResult> mapChunk({
    required String shortVideoPath,
    required String chunkPath,
    required int chunkIndex,
    double chunkOffsetSeconds = 0,
  }) async {
    if (_model == null) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API not configured');
    }

    final shortFile = File(shortVideoPath);
    final chunkFile = File(chunkPath);

    if (!await shortFile.exists()) {
      throw Exception('Short video file not found: $shortVideoPath');
    }
    if (!await chunkFile.exists()) {
      throw Exception('Chunk video file not found: $chunkPath');
    }

    final shortBytes = await shortFile.readAsBytes();
    final chunkBytes = await chunkFile.readAsBytes();

    final content = [
      Content.multi([
        DataPart('video/mp4', shortBytes),
        DataPart('video/mp4', chunkBytes),
        TextPart(CHUNK_MAP_PROMPT),
      ])
    ];

    try {
      final response = await _model!.generateContent(content);
      final text = response.text ?? '';
      if (text.trim().isEmpty) {
        throw GeminiException(GeminiErrorKind.empty, 'Empty response received from model');
      }

      final matches = parseMatches(
        text,
        chunkIndex: chunkIndex,
        chunkOffsetSeconds: chunkOffsetSeconds,
        modelName: _selectedModel,
      );

      final warning = checkSuspiciousOutput(text, matches);

      return ChunkMapResult(
        rawText: text,
        matches: matches,
        warning: warning,
        tokensUsed: response.usageMetadata?.totalTokenCount,
      );
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException(_classifyError(e), e.toString());
    }
  }

  /// Run verification on short clip vs extracted movie candidate clip
  Future<VerifyResult> verifyCandidate({
    required String shortClipPath,
    required String movieClipPath,
  }) async {
    if (_model == null) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API not configured');
    }

    final shortBytes = await File(shortClipPath).readAsBytes();
    final movieBytes = await File(movieClipPath).readAsBytes();

    final content = [
      Content.multi([
        DataPart('video/mp4', shortBytes),
        DataPart('video/mp4', movieBytes),
        TextPart(VERIFY_PROMPT),
      ])
    ];

    try {
      final response = await _model!.generateContent(content);
      final text = response.text ?? '';

      final verdict = parseVerdict(text);
      return VerifyResult(
        same: verdict?.same ?? false,
        reason: verdict?.reason ?? 'No clear verdict provided',
        rawText: text,
      );
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException(_classifyError(e), e.toString());
    }
  }

  /// Parse matches from HISSA 2 lines in model output
  List<ChunkMatch> parseMatches(
    String raw, {
    required int chunkIndex,
    required double chunkOffsetSeconds,
    required String modelName,
  }) {
    final matches = <ChunkMatch>[];
    // Supports standard formats matching regex from lib/gemini.ts:
    // "Short 00:18.042 - 00:19.125 --> Movie 00:00.000 - 00:01.083"
    // "Short: 00:18.042 to 00:19.125 -> Movie: 00:00.000 to 00:01.083"
    final regex = RegExp(
      r'(?:^|\n)\s*(?:[-*•]\s*)?Short[:\s]+((?:\d+:)?\d+:\d+(?:\.\d+)?)\s*(?:-|–|to)\s*((?:\d+:)?\d+:\d+(?:\.\d+)?)\s*(?:-->|->|—>|=>|→)\s*Movie[:\s]+((?:\d+:)?\d+:\d+(?:\.\d+)?)\s*(?:-|–|to)\s*((?:\d+:)?\d+:\d+(?:\.\d+)?)',
      caseSensitive: false,
    );

    for (final match in regex.allMatches(raw)) {
      final shortStart = _parseTimestamp(match.group(1)!);
      final shortEnd = _parseTimestamp(match.group(2)!);
      final movieLocalStart = _parseTimestamp(match.group(3)!);
      final movieLocalEnd = _parseTimestamp(match.group(4)!);

      if (shortStart != null &&
          shortEnd != null &&
          movieLocalStart != null &&
          movieLocalEnd != null &&
          shortEnd > shortStart &&
          movieLocalEnd > movieLocalStart) {
        matches.add(ChunkMatch(
          shortStart: shortStart,
          shortEnd: shortEnd,
          movieStart: chunkOffsetSeconds + movieLocalStart,
          movieEnd: chunkOffsetSeconds + movieLocalEnd,
          chunkIndex: chunkIndex,
          model: modelName,
        ));
      }
    }

    return matches;
  }

  /// Detect false positive extrapolation drift or missing "NOT FOUND"
  String? checkSuspiciousOutput(String raw, List<ChunkMatch> matches) {
    if (!raw.toUpperCase().contains('NOT FOUND')) {
      return 'Notice: Output contains no NOT FOUND lines (all segments mapped). Check for false positives.';
    }
    if (matches.length >= 4) {
      final offsets = matches.map((m) => m.movieStart - m.shortStart).toList();
      final minOff = offsets.reduce((a, b) => a < b ? a : b);
      final maxOff = offsets.reduce((a, b) => a > b ? a : b);
      if ((maxOff - minOff).abs() < 0.25) {
        return 'Warning: Matches follow an identical constant offset. Possible extrapolation drift.';
      }
    }
    return null;
  }

  /// Parse verifier verdict line: VERDICT: SAME vs DIFFERENT
  ({bool same, String reason})? parseVerdict(String raw) {
    final verdictMatches = RegExp(r'VERDICT\s*:\s*(SAME|DIFFERENT)', caseSensitive: false).allMatches(raw).toList();
    if (verdictMatches.isEmpty) return null;

    final lastVerdict = verdictMatches.last.group(1)!.toUpperCase() == 'SAME';
    final reasonMatches = RegExp(r'REASON\s*:\s*(.+)', caseSensitive: false).allMatches(raw).toList();
    final reason = reasonMatches.isNotEmpty ? reasonMatches.last.group(1)!.trim() : '';

    return (same: lastVerdict, reason: reason);
  }

  double? _parseTimestamp(String ts) {
    final clean = ts.trim();
    final parts = clean.split(':');
    if (parts.length == 2) {
      final m = double.tryParse(parts[0]);
      final s = double.tryParse(parts[1]);
      if (m != null && s != null) return m * 60 + s;
    } else if (parts.length == 3) {
      final h = double.tryParse(parts[0]);
      final m = double.tryParse(parts[1]);
      final s = double.tryParse(parts[2]);
      if (h != null && m != null && s != null) return h * 3600 + m * 60 + s;
    }
    return null;
  }

  GeminiErrorKind _classifyError(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('api key') || msg.contains('invalid_argument')) return GeminiErrorKind.invalidKey;
    if (msg.contains('429') || msg.contains('rate limit') || msg.contains('tpm') || msg.contains('rpm')) {
      return GeminiErrorKind.rateLimited;
    }
    if (msg.contains('quota') || msg.contains('generaterequestsperday') || msg.contains('per day')) {
      return GeminiErrorKind.quotaExhausted;
    }
    if (msg.contains('prohibited') || msg.contains('safety') || msg.contains('policy')) {
      return GeminiErrorKind.policyBlocked;
    }
    if (msg.contains('503') || msg.contains('unavailable') || msg.contains('overloaded') || msg.contains('500')) {
      return GeminiErrorKind.unavailable;
    }
    if (msg.contains('socket') || msg.contains('network') || msg.contains('connection') || msg.contains('handshake')) {
      return GeminiErrorKind.network;
    }
    return GeminiErrorKind.other;
  }
}
