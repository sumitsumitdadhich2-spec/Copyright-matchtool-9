/// 1:1 Port of lib/gemini.ts prompts and parsers

class GeminiError implements Exception {
  final String kind; // 'rpd' | 'rate' | 'policy_blocked' | 'empty' | 'unavailable' | 'invalid_key' | 'other'
  final String message;

  GeminiError(this.kind, this.message);

  @override
  String toString() => 'GeminiError($kind): $message';
}

GeminiError classifyGeminiError(dynamic err) {
  if (err is GeminiError) return err;
  final msg = err.toString();
  final lower = msg.toLowerCase();

  if (lower.contains('api_key_invalid') ||
      lower.contains('api key not valid') ||
      lower.contains('apikey') && lower.contains('invalid') ||
      lower.contains('unauthenticated') ||
      lower.contains('permission_denied') && lower.contains('key')) {
    return GeminiError('invalid_key', msg);
  }

  if (lower.contains('503') ||
      lower.contains('unavailable') ||
      lower.contains('high demand') ||
      lower.contains('service unavailable') ||
      lower.contains('model is overloaded')) {
    return GeminiError('unavailable', msg);
  }

  final isExplicitDaily = lower.contains('resource_exhausted') &&
          (lower.contains('daily') || lower.contains('per_day') || lower.contains('perday')) ||
      lower.contains('check quota: generatescontent') ||
      lower.contains('exceeded your current quota') ||
      lower.contains('generaterequestsperday') ||
      lower.contains('_per_model_per_user') ||
      (lower.contains('daily') && lower.contains('quota')) ||
      (lower.contains('limit: 20') && lower.contains('daily')) ||
      (lower.contains('limit: 25000000') || lower.contains('limit: 50000000') || lower.contains('limit: 100000000'));

  if (isExplicitDaily) {
    return GeminiError('rpd', msg);
  }

  if (lower.contains('prohibited_content') ||
      lower.contains('blocked_by_safety') ||
      lower.contains('safety_ratings_blocked') ||
      lower.contains('block_reason: prohibited_content') ||
      lower.contains('prompt block reason: prohibited_content') ||
      lower.contains('finishreason=safety') ||
      lower.contains('finish reason: safety') ||
      lower.contains('finish reason: blocklist') ||
      lower.contains('finish reason: prohibited_content') ||
      lower.contains('harm_category') ||
      (lower.contains('safety') && lower.contains('ratings'))) {
    return GeminiError('policy_blocked', msg);
  }

  final is429 = lower.contains('429') ||
      lower.contains('resource_exhausted') ||
      lower.contains('resource has been exhausted') ||
      lower.contains('quota') ||
      lower.contains('rate limit') ||
      lower.contains('limit:') ||
      lower.contains('exhausted') ||
      lower.contains('per minute') ||
      lower.contains('rpm') ||
      lower.contains('tpm');

  if (is429) {
    return GeminiError('rate', msg);
  }

  if (lower.contains('empty') && (lower.contains('response') || lower.contains('finder') || lower.contains('model'))) {
    return GeminiError('empty', msg);
  }

  return GeminiError('other', msg);
}

String fmtClock(double sec) {
  final s = sec.round().clamp(0, 999999);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = s % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

const int MINUTE_FINDER_SHORT_FPS = 10;
const int BACKUP_FRAME_BUDGET = 900;
const int BACKUP_MIN_FPS = 5;
const int BACKUP_MAX_FPS = 24;

int backupClipFps(double clipSeconds) {
  final f = (BACKUP_FRAME_BUDGET / (clipSeconds <= 0 ? 1.0 : clipSeconds)).floor();
  return f.clamp(BACKUP_MIN_FPS, BACKUP_MAX_FPS);
}

const String MINUTE_FINDER_PROMPT = r'''You are a forensic video analyst. You are given TWO videos:
- Video 1: a SHORT VIDEO that was edited together from clips of a movie (sampled at 10 fps).
- Video 2: a 20-MINUTE WINDOW of the original movie, covering movie time {{WINDOW_START}} to {{WINDOW_END}} (sampled at 1 fps).

Tumhara kaam frame-perfect mapping NAHI hai. Tumhara kaam ye batana hai ki Video 1 ke kaun se scenes Video 2 ke andar hain, aur movie ke KAUN SE MINUTE(S) par hain — taaki agla step un minutes ko 24 fps par frame-by-frame check kar sake.

Respond in Hinglish (Hindi written in Latin script). Spoken dialogue must always be QUOTED VERBATIM in its original language.

Your answer has exactly THREE parts:

=====================
HISSA 1 — SHORT VIDEO SCENE MAP
=====================
Watch Video 1 from start to finish and break it into SCENES (shot/scene changes par cut karo):
- Har scene 1 se ~10 second ka ho. Jab bhi location, camera setup, ya action clearly badle to naya scene shuru karo. Ek lambi continuous shot ko bhi 5-6 second ke tukdon me todo.
- Scenes contiguous hone chahiye: har scene ka start = pichle scene ka end. Pehla scene 00:00 se shuru ho, aakhri scene video ki total duration par khatam ho. Koi gap nahi, koi overlap nahi.
- Har line ka format:
  S<n>: mm:ss - mm:ss | <location + kaun kya kar raha hai, max 15 words> | DIALOGUE: "<exact quoted words>" ya NONE
- Dialogue sabse strong fingerprint hai — kabhi summarize mat karo, hamesha exact words quote karo. Agar audio mute/music se daba hua hai to DIALOGUE: MUTED likho.
- Description lambi mat karo — output token budget limited hai.

=====================
HISSA 2 — MOVIE LOCATION HUNT
=====================
Ab HISSA 1 ke HAR EK scene ke liye Video 2 (movie window) me EXACT wahi footage dhundho (same recording — sirf similar scene nahi).

Search method (har scene ke liye follow karo):
- PASS 1 (AUDIO LOCATE): Agar scene me dialogue hai, to sabse pehle Video 2 ke audio me wahi exact words dhundho. Dialogue sabse tez aur sabse reliable locator hai. Jahan words mile, us position ke frames dekho.
- PASS 2 (VISUAL LOCATE): Dialogue na ho (ya MUTED ho) to Video 2 ko shuru se aakhir tak scan karo aur wo jagah dhundho jahan same location + same actors + same costume + same action ho. Mile to +-5 second ke frames dekh kar confirm karo ki action ka ORDER bhi same hai.
- PASS 3 (CONFIRM): Match tab hi hai jab (a) dialogue words same hain YA (b) actions ka sequence same hai. Sirf "same actor, same location" MATCH nahi hai — wo alag moment ho sakta hai.

STRICT RULES:
1. Movie timestamps Video 2 ki APNI clock se aane chahiye — frames/audio ko actually dekh-sun kar. Short video ke timestamps copy karke movie column me daalna FORBIDDEN hai.
2. NO EXTRAPOLATION (CRITICAL): Ek scene ka offset mil jane ke baad "short_time + offset" formula se baaki scenes AUTOMATICALLY map karna STRICTLY FORBIDDEN hai. Short video EDITED hai — uske scenes movie me alag-alag jagah se, alag order me aa sakte hain. Har scene ko independently dhundho aur independently verify karo. Agar tumhare consecutive matches ek fixed offset follow kar rahe hain, RUK JAO aur har ek dobara verify karo.
3. DIALOGUE VERIFICATION: Dialogue wale scene ka match tab hi valid hai jab WAHI words Video 2 ke audio me us position par actually SUNAI dein. Words alag = NOT FOUND (ya POSSIBLE agar audio unclear ho).
4. QUALITY DIFFERENCE IS NOT DIFFERENT: crop, zoom, letterbox, aspect-ratio change, compression, blur, color-grade, brightness, watermark, text overlay, subtitles, added music, original audio replaced/muted, mirrored image, thoda speed-up/slow-down — ye sab IGNORE karo. Underlying footage same hai to wo MATCH hai. In wajahon se match reject karna FORBIDDEN hai.
5. WINDOW KA END = FOOTAGE KA END: Ye window poori movie ka sirf 20-minute tukda hai. Short ke bahut se scenes is window me honge hi NAHI — wo movie ke doosre hisse me hain. Ye NORMAL aur EXPECTED hai. Agar POORA short is window me na mile to saaf likho — zabardasti match banana FORBIDDEN hai.
6. SIMILAR IS NOT SAME: same actors, same location, same costume par DIFFERENT moment (alag dialogue, alag action) = NOT FOUND. Lekin agar tumhe strong shak hai ki footage yahi minute ke aas-paas hai par tum confirm nahi kar paaye (audio unclear, fast cuts, low fps), to use NOT FOUND mat likho — POSSIBLE likho with reason. POSSIBLE minutes agle step me 24 fps par check ho jayenge, isliye miss karne se behtar hai POSSIBLE dena.
7. Har scene ke liye movie ka minute do tarah likho:
   - WINDOW time: Video 2 ki apni clock (00:00 se 20:00)
   - MOVIE time: WINDOW time + {{WINDOW_START}} (absolute movie time)
   Agar Video 2 ka player/clock already absolute movie time dikha raha hai (e.g. {{WINDOW_START}} se shuru), to WINDOW aur MOVIE dono me wahi absolute time likho aur ek line me note karo: "CLOCK: absolute".
8. Ek short scene movie me EK jagah hi hoti hai. Agar tumhe do jagah lag rahi hain, to jo dialogue/action se zyada confirm hai use MATCH aur doosri ko POSSIBLE likho.
9. FINAL SELF-CHECK: Answer dene se pehle har MATCH dobara dekho — (a) kya dialogue ya action sequence sach me same hai? (b) kya movie timestamp Video 2 ki apni clock se aaya hai, formula se nahi? Jo match sirf "pichle match ke baad aata hai isliye" bana hai, use POSSIBLE ya NOT FOUND me badlo.

Har scene ki line ka format (teen me se ek):
  S<n> --> MATCH | WINDOW mm:ss - mm:ss | MOVIE mm:ss - mm:ss | EVIDENCE: <dialogue words jo sune / action jo dikha, max 15 words>
  S<n> --> POSSIBLE | WINDOW mm:ss - mm:ss | MOVIE mm:ss - mm:ss | REASON: <kya same laga, kya confirm nahi hua>
  S<n> --> NOT FOUND — <chhota reason: is window me ye scene nahi hai / alag moment hai>

=====================
HISSA 3 — MINUTE LIST (FINAL)
=====================
HISSA 2 ke saare MATCH aur POSSIBLE se movie ke minutes nikaalo (MOVIE time ke hisaab se, absolute). Har wo minute jisme matched footage ka koi bhi hissa aata hai, list me aayega (e.g. MOVIE 23:50 - 24:10 => minute 23 aur 24 dono).

Exact format, aur kuch nahi:
MATCH MINUTES: <comma separated minute numbers, ascending, e.g. 23, 24, 31> (ya NONE)
POSSIBLE MINUTES: <comma separated minute numbers> (ya NONE)
WINDOW VERDICT: FOUND (agar kam se kam ek MATCH) / POSSIBLE ONLY / NOT IN THIS WINDOW

Poore answer me sirf HISSA 1, HISSA 2 aur HISSA 3 do, aur kuch nahi.''';

String buildMinuteFinderPrompt(double startOffsetSec, double endOffsetSec) {
  return MINUTE_FINDER_PROMPT
      .replaceAll('{{WINDOW_START}}', fmtClock(startOffsetSec))
      .replaceAll('{{WINDOW_END}}', fmtClock(endOffsetSec));
}

const String BACKUP_MINUTE_FINDER_PROMPT = r'''You are a forensic video analyst doing a SECOND, FOCUSED search. You are given TWO videos:
- Video 1: a SHORT CLIP cut out of a short video. Ye short video movie ke clips se edit karke banaya gaya tha. Is clip me sirf wo hisse hain jo PEHLI search me movie ke KISI BHI hisse me nahi mile. Clip is sampled at {{CLIP_FPS}} fps (high), so you have many frames per second.
- Video 2: a 20-MINUTE WINDOW of the original movie, covering movie time {{WINDOW_START}} to {{WINDOW_END}} (sampled at 1 fps).

CLIP PART MAP (Video 1 ki apni clock 00:00 se shuru hoti hai; har PART short video ke asli time se aata hai; PARTS ke beech 1 second black + silence hai):
{{PART_MAP}}

CONTEXT FROM FIRST SEARCH (short ke baaki hisse movie me yahan mile the — ye sirf hint hai, is se koi timestamp CALCULATE mat karna):
{{FOUND_SUMMARY}}

Tumhara kaam frame-perfect mapping NAHI hai. Tumhara kaam ye batana hai ki Video 1 ke PARTS Video 2 ke andar hain ya nahi, aur hain to movie ke KAUN SE MINUTE(S) par — taaki agla step un minutes ko 24 fps par frame-by-frame check kar sake.

Ye clip pehli baar MISS hua tha. Iska matlab ye ho sakta hai: (a) footage movie me hai lekin fast cuts / chhote shots / dark scene / heavy crop ki wajah se pehli baar pakda nahi gaya, YA (b) ye footage movie ka hai hi nahi (text card, channel intro/outro, logo, doosri film ka footage). Dono possibilities kholi rakho. Zabardasti match banana FORBIDDEN hai, lekin genuine shak ho to POSSIBLE dena ZAROORI hai.

Respond in Hinglish (Hindi written in Latin script). Spoken dialogue must always be QUOTED VERBATIM in its original language.

Your answer has exactly THREE parts:

=====================
HISSA 1 — CLIP PART MAP (LIGHT)
=====================
Video 1 ko dekho. Har PART ke liye:
- PART ko 1 se max 3 scenes me todo. Agar poora PART ek hi continuous shot/scene hai to ek hi line likho. Chhote-chhote tukde banana ZAROORI NAHI hai.
- Do alag PARTS ko kabhi ek scene me merge mat karo — black frame par hamesha naya PART shuru hota hai.
- Har scene me clip time aur SHORT time (PART MAP se) dono likho.
- Har PART ka TYPE tag do: MOVIE-FOOTAGE (asli film ka shot dikh raha hai) / TEXT-CARD (sirf text/graphics) / LOGO-INTRO-OUTRO (channel branding) / NON-MOVIE (koi aur footage, vlog, reaction, etc.).
- Har line ka format:
  P<part>-S<n>: clip mm:ss - mm:ss | short mm:ss - mm:ss | TYPE: <tag> | <location + kaun kya kar raha hai, max 15 words> | DIALOGUE: "<exact quoted words>" ya NONE ya MUTED
- Dialogue sabse strong fingerprint hai — kabhi summarize mat karo, exact words quote karo. Background music/SFX bhi note karo agar distinctive ho (e.g. "gunshot", "specific song").
- High fps hai isliye chhote details bhi note karo jo pehli baar miss ho sakte the: props, text on screen, costume detail, camera move, background objects.

=====================
HISSA 2 — DEEP MOVIE HUNT
=====================
HISSA 1 ke HAR EK scene ke liye Video 2 (movie window) me EXACT wahi footage dhundho (same recording — sirf similar scene nahi).

Search method (har scene ke liye follow karo, order me):
- PASS 1 (AUDIO LOCATE — primary): Video 2 ka audio 1 fps frames se ZYADA reliable hai kyunki audio poora hota hai. Dialogue ho to exact words dhundho. Dialogue na ho to distinctive music cue, SFX, ambient sound (crowd, rain, engine) dhundho. Jahan mile, us position ke +-10 second ke frames dekho.
- PASS 2 (VISUAL LOCATE): Video 2 ko shuru se aakhir tak scan karo — same location + same actors + same costume + same props. High-fps clip ke details (HISSA 1 me note kiye) ko movie frames me dhundho. Ye clip pehle miss hua tha, isliye DARK scenes, FAST-CUT sequences, CLOSE-UPS, aur heavily CROPPED shots ko extra dhyan se dekho — wahi sabse zyada miss hote hain.
- PASS 3 (CONFIRM): MATCH tab hi jab (a) dialogue words same hain YA (b) actions ka sequence same hai YA (c) distinctive audio cue + same visual setup dono milte hain. Sirf "same actor, same location" MATCH nahi — POSSIBLE ho sakta hai.

STRICT RULES:
1. Movie timestamps Video 2 ki APNI clock se — frames/audio actually dekh-sun kar. Clip time ya short time ko movie column me copy karna FORBIDDEN.
2. NO EXTRAPOLATION (CRITICAL): CONTEXT FROM FIRST SEARCH se ya kisi offset formula se movie time CALCULATE karna STRICTLY FORBIDDEN. Context sirf ye batata hai ki short ke aas-paas ke hisse kahan mile the — missing hissa kahin bhi ho sakta hai (short EDITED hai, order alag ho sakta hai). Agar context ke hint wali jagah check karo, to actually frames/audio dekh kar confirm karo — assume mat karo.
3. DIALOGUE VERIFICATION: Dialogue wale scene ka MATCH tab hi jab WAHI words Video 2 ke audio me us position par SUNAI dein. Words alag = NOT FOUND (ya POSSIBLE agar audio unclear).
4. QUALITY DIFFERENCE IS NOT DIFFERENT: crop, zoom, letterbox, aspect-ratio, compression, blur, color-grade, brightness, watermark, text overlay, subtitles, added music, original audio replaced/muted, mirrored image, speed change — IGNORE. Underlying footage same = MATCH. In wajahon se reject karna FORBIDDEN.
5. LOW-FPS MOVIE SIDE: Video 2 me 1 fps hai. Agar clip ka scene movie me sirf 1-3 frames me dikh raha hai lekin location + costume + audio cue match karte hain, to use NOT FOUND mat karo — POSSIBLE likho with reason "1fps par kam frames, audio/setup match". Agla step 24 fps par verify karega.
6. WINDOW KA END = FOOTAGE KA END: Ye poori movie ka sirf 20-minute tukda hai. Clip is window me na ho ye NORMAL aur EXPECTED hai — saaf likho NOT FOUND. Pehli baar miss hone ka matlab ye NAHI ki isi window me hona chahiye.
7. TEXT-CARD / LOGO / NON-MOVIE type PARTS ke liye movie me dhundhne ki koshish karo lekin agar clearly movie footage nahi hai to seedha NOT FOUND — "NON-MOVIE" reason ke saath. Zabardasti match mat banao.
8. SIMILAR IS NOT SAME: same actors, same location, same costume par DIFFERENT moment = NOT FOUND. Lekin strong shak + confirm nahi kar paaye = POSSIBLE with reason. Backup search me miss karna sabse bura hai — POSSIBLE dene me generous raho, MATCH dene me strict.
9. Har scene ke liye movie ka minute do tarah:
   - WINDOW time: Video 2 ki apni clock (00:00 se 20:00)
   - MOVIE time: WINDOW time + {{WINDOW_START}} (absolute)
   Agar Video 2 ka clock already absolute movie time dikha raha hai, to dono me wahi absolute time likho aur ek line me note karo: "CLOCK: absolute".
10. Ek clip scene movie me EK jagah hi hoti hai. Do jagah lage to zyada confirm wali MATCH, doosri POSSIBLE.
11. FINAL SELF-CHECK: har MATCH dobara dekho — (a) dialogue/action/audio-cue sach me same? (b) timestamp Video 2 ki clock se aaya, formula ya context-hint se nahi? Jo match sirf "context me aas-paas mila tha isliye" bana hai, use POSSIBLE ya NOT FOUND me badlo.

Har scene ki line ka format (teen me se ek) — SHORT time ZAROOR likho (clip time nahi):
  P<part>-S<n> --> MATCH | SHORT mm:ss - mm:ss | WINDOW mm:ss - mm:ss | MOVIE mm:ss - mm:ss | EVIDENCE: <dialogue words / action / audio cue, max 15 words>
  P<part>-S<n> --> POSSIBLE | SHORT mm:ss - mm:ss | WINDOW mm:ss - mm:ss | MOVIE mm:ss - mm:ss | REASON: <kya same laga, kya confirm nahi hua>
  P<part>-S<n> --> NOT FOUND — <chhota reason: is window me nahi / alag moment / NON-MOVIE>

=====================
HISSA 3 — MINUTE LIST (FINAL)
=====================
HISSA 2 ke saare MATCH aur POSSIBLE se movie ke minutes nikaalo (MOVIE time, absolute). Har wo minute jisme matched footage ka koi bhi hissa aata hai, list me aayega (e.g. MOVIE 23:50 - 24:10 => 23 aur 24 dono).

Exact format, aur kuch nahi:
  MATCH MINUTES: <comma separated minute numbers, ascending> (ya NONE)
  POSSIBLE MINUTES: <comma separated minute numbers> (ya NONE)
  PART STATUS: P1=<FOUND/POSSIBLE/NOT-HERE/NON-MOVIE>, P2=<...>, ...
  WINDOW VERDICT: FOUND (kam se kam ek MATCH) / POSSIBLE ONLY / NOT IN THIS WINDOW

Poore answer me sirf HISSA 1, HISSA 2 aur HISSA 3 do, aur kuch nahi.''';

class BackupPartSpec {
  final int index;
  final double clipStart;
  final double clipEnd;
  final double shortStart;
  final double shortEnd;

  BackupPartSpec({
    required this.index,
    required this.clipStart,
    required this.clipEnd,
    required this.shortStart,
    required this.shortEnd,
  });
}

String buildPartMap(List<BackupPartSpec> parts) {
  return parts
      .map((p) => 'PART ${p.index}: clip ${fmtClock(p.clipStart)} - ${fmtClock(p.clipEnd)}  =  short ${fmtClock(p.shortStart)} - ${fmtClock(p.shortEnd)}')
      .join('\n');
}

String buildBackupMinuteFinderPrompt(
  double startOffsetSec,
  double endOffsetSec,
  int clipFps,
  List<BackupPartSpec> parts,
  String foundSummary,
) {
  return BACKUP_MINUTE_FINDER_PROMPT
      .replaceAll('{{WINDOW_START}}', fmtClock(startOffsetSec))
      .replaceAll('{{WINDOW_END}}', fmtClock(endOffsetSec))
      .replaceAll('{{CLIP_FPS}}', clipFps.toString())
      .replaceAll('{{PART_MAP}}', buildPartMap(parts))
      .replaceAll('{{FOUND_SUMMARY}}', foundSummary.trim().isEmpty ? 'NONE' : foundSummary.trim());
}

double? parseTsFlexible(String ts) {
  final t = ts.trim();
  final m3 = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2}(?:\.\d+)?)$').firstMatch(t);
  if (m3 != null) {
    return double.parse(m3.group(1)!) * 3600 + double.parse(m3.group(2)!) * 60 + double.parse(m3.group(3)!);
  }
  final m2 = RegExp(r'^(\d+):(\d{1,2}(?:\.\d+)?)$').firstMatch(t);
  if (m2 != null) {
    return double.parse(m2.group(1)!) * 60 + double.parse(m2.group(2)!);
  }
  return null;
}

class MinuteFinderHit {
  final int scene;
  final String sceneId;
  final int? part;
  final String kind; // 'match' | 'possible'
  final double? shortStart;
  final double? shortEnd;
  final double fileStart;
  final double fileEnd;
  final String evidence;

  MinuteFinderHit({
    required this.scene,
    required this.sceneId,
    this.part,
    required this.kind,
    this.shortStart,
    this.shortEnd,
    required this.fileStart,
    required this.fileEnd,
    required this.evidence,
  });
}

class MinuteFinderParse {
  final List<MinuteFinderHit> hits;
  final List<int> matchMinutes;
  final List<int> possibleMinutes;
  final bool clockAbsolute;
  final Map<int, String>? partTypes;
  final Map<int, String>? partStatus;

  MinuteFinderParse({
    required this.hits,
    required this.matchMinutes,
    required this.possibleMinutes,
    required this.clockAbsolute,
    this.partTypes,
    this.partStatus,
  });
}

Map<String, double>? _clipToShort(List<BackupPartSpec> parts, double clipStart, double clipEnd, [int? preferPart]) {
  final mid = (clipStart + clipEnd) / 2;
  final p = (preferPart != null ? parts.where((x) => x.index == preferPart).firstOrNull : null) ??
      parts.where((x) => mid >= x.clipStart - 0.5 && mid <= x.clipEnd + 0.5).firstOrNull;
  if (p == null) return null;
  final off = p.shortStart - p.clipStart;
  final s = [p.shortStart, clipStart + off].reduce((a, b) => a > b ? a : b);
  final e = [p.shortEnd, clipEnd + off].reduce((a, b) => a < b ? a : b);
  return e > s ? {'start': s, 'end': e} : {'start': p.shortStart, 'end': p.shortEnd};
}

MinuteFinderParse parseFinderGeneric(
  String raw,
  double startOffset,
  double endOffset,
  bool assumeRelative,
  List<BackupPartSpec>? parts,
) {
  final windowLen = endOffset - startOffset;
  final clockAbsolute = RegExp(r'CLOCK\s*:\s*absolute', caseSensitive: false).hasMatch(raw);
  final backup = parts != null;
  const tsPattern = r'(\d+:\d{1,2}(?::\d{1,2})?(?:\.\d+)?)';

  final shortMap = <String, Map<String, double>>{};
  final partTypes = <int, String>{};

  final sceneRe = backup
      ? RegExp(r'^\s*P(\d+)\s*-\s*S(\d+)\s*:\s*(?:clip\s*)?' + tsPattern + r'\s*-\s*' + tsPattern + r'([^\n]*)', multiLine: true, caseSensitive: false)
      : RegExp(r'^\s*S(\d+)\s*:\s*' + tsPattern + r'\s*-\s*' + tsPattern, multiLine: true, caseSensitive: false);

  for (final sm in sceneRe.allMatches(raw)) {
    if (backup) {
      final part = int.parse(sm.group(1)!);
      final id = 'P$part-S${sm.group(2)}';
      final rest = sm.group(5) ?? '';
      final shortCol = RegExp(r'short\s*:?\s*' + tsPattern + r'\s*-\s*' + tsPattern, caseSensitive: false).firstMatch(rest);
      Map<String, double>? sw;
      if (shortCol != null) {
        final s = parseTsFlexible(shortCol.group(1)!);
        final e = parseTsFlexible(shortCol.group(2)!);
        if (s != null && e != null && e > s) sw = {'start': s, 'end': e};
      }
      if (sw == null) {
        final cs = parseTsFlexible(sm.group(3)!);
        final ce = parseTsFlexible(sm.group(4)!);
        if (cs != null && ce != null && ce > cs) sw = _clipToShort(parts, cs, ce, part);
      }
      if (sw != null && !shortMap.containsKey(id)) shortMap[id] = sw;
      final typeMatch = RegExp(r'TYPE\s*:\s*([A-Z][A-Z\-\s]*?)(?=\s*\||$)', caseSensitive: false).firstMatch(rest);
      if (typeMatch != null && !partTypes.containsKey(part)) {
        partTypes[part] = typeMatch.group(1)!.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '-');
      }
    } else {
      final s = parseTsFlexible(sm.group(2)!);
      final e = parseTsFlexible(sm.group(3)!);
      if (s == null || e == null || e <= s) continue;
      final id = 'S${sm.group(1)}';
      if (!shortMap.containsKey(id)) shortMap[id] = {'start': s, 'end': e};
    }
  }

  bool inWindow(double t) => t >= startOffset - 5 && t <= endOffset + 5;
  bool inRelative(double t) => t >= -1 && t <= windowLen + 5;

  double? resolve(double? win, double? mov) {
    if (win != null) {
      if (clockAbsolute) return inWindow(win) ? win : inRelative(win) ? startOffset + win : null;
      if (inRelative(win) && (assumeRelative || !inWindow(win) || startOffset == 0)) return startOffset + win;
      if (inWindow(win)) return win;
      if (inRelative(win)) return startOffset + win;
    }
    if (mov != null) {
      if (inWindow(mov)) return mov;
      if (inRelative(mov)) return startOffset + mov;
    }
    return null;
  }

  final hits = <MinuteFinderHit>[];

  final hitRe = backup
      ? RegExp(r'^\s*P(\d+)\s*-\s*S(\d+)\s*-->\s*(MATCH|POSSIBLE)\s*\|([^\n]+)', multiLine: true, caseSensitive: false)
      : RegExp(r'^\s*S(\d+)\s*-->\s*(MATCH|POSSIBLE)\s*\|([^\n]+)', multiLine: true, caseSensitive: false);

  for (final m in hitRe.allMatches(raw)) {
    final int sceneNum;
    final String sceneId;
    final int? partNum;
    final String kind;
    final String body;

    if (backup) {
      partNum = int.parse(m.group(1)!);
      sceneNum = int.parse(m.group(2)!);
      sceneId = 'P$partNum-S$sceneNum';
      kind = m.group(3)!.toLowerCase();
      body = m.group(4)!;
    } else {
      partNum = null;
      sceneNum = int.parse(m.group(1)!);
      sceneId = 'S$sceneNum';
      kind = m.group(2)!.toLowerCase();
      body = m.group(3)!;
    }

    final winMatch = RegExp(r'WINDOW\s*:?\s*([0-9:.,\s\-]+?)(?=\s*\||$)', caseSensitive: false).firstMatch(body);
    final movMatch = RegExp(r'MOVIE\s*:?\s*([0-9:.,\s\-]+?)(?=\s*\||$)', caseSensitive: false).firstMatch(body);
    final evMatch = RegExp(r'(?:EVIDENCE|REASON)\s*:\s*([^|\n]+)', caseSensitive: false).firstMatch(body);
    final evidence = evMatch?.group(1)?.trim() ?? '';

    final rangePairRe = RegExp(tsPattern + r'\s*-\s*' + tsPattern);
    final winRanges = winMatch != null ? rangePairRe.allMatches(winMatch.group(1)!).toList() : <RegExpMatch>[];
    final movRanges = movMatch != null ? rangePairRe.allMatches(movMatch.group(1)!).toList() : <RegExpMatch>[];

    final maxCount = [winRanges.length, movRanges.length, 1].reduce((a, b) => a > b ? a : b);

    for (int i = 0; i < maxCount; i++) {
      final w = i < winRanges.length ? winRanges[i] : null;
      final mv = i < movRanges.length ? movRanges[i] : null;

      final wStart = w != null ? parseTsFlexible(w.group(1)!) : null;
      final wEnd = w != null ? parseTsFlexible(w.group(2)!) : null;
      final mStart = mv != null ? parseTsFlexible(mv.group(1)!) : null;
      final mEnd = mv != null ? parseTsFlexible(mv.group(2)!) : null;

      final fileStart = resolve(wStart, mStart);
      final fileEnd = resolve(wEnd, mEnd);

      if (fileStart != null && fileEnd != null && fileEnd > fileStart) {
        hits.add(MinuteFinderHit(
          scene: sceneNum,
          sceneId: sceneId,
          part: partNum,
          kind: kind == 'match' ? 'match' : 'possible',
          shortStart: shortMap[sceneId]?['start'],
          shortEnd: shortMap[sceneId]?['end'],
          fileStart: fileStart,
          fileEnd: fileEnd,
          evidence: evidence,
        ));
      }
    }
  }

  // Parse HISSA 3 Final minutes
  final matchMinSet = <int>{};
  final possMinSet = <int>{};

  final mmMatch = RegExp(r'MATCH MINUTES\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
  if (mmMatch != null) {
    for (final numM in RegExp(r'\b\d+\b').allMatches(mmMatch.group(1)!)) {
      final val = int.tryParse(numM.group(0)!);
      if (val != null) matchMinSet.add(val);
    }
  }

  final pmMatch = RegExp(r'POSSIBLE MINUTES\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
  if (pmMatch != null) {
    for (final numM in RegExp(r'\b\d+\b').allMatches(pmMatch.group(1)!)) {
      final val = int.tryParse(numM.group(0)!);
      if (val != null) possMinSet.add(val);
    }
  }

  // Fallback: collect minutes directly from hits
  if (matchMinSet.isEmpty && possMinSet.isEmpty) {
    for (final h in hits) {
      final sMin = (h.fileStart / 60.0).floor();
      final eMin = ((h.fileEnd - 0.001) / 60.0).floor();
      for (int m = sMin; m <= eMin; m++) {
        if (h.kind == 'match') {
          matchMinSet.add(m);
        } else {
          possMinSet.add(m);
        }
      }
    }
  }

  return MinuteFinderParse(
    hits: hits,
    matchMinutes: matchMinSet.toList()..sort(),
    possibleMinutes: possMinSet.toList()..sort(),
    clockAbsolute: clockAbsolute,
    partTypes: partTypes.isEmpty ? null : partTypes,
  );
}

MinuteFinderParse parseMinuteFinderOutput(String raw, double startOffset, double endOffset, bool assumeRelative) {
  return parseFinderGeneric(raw, startOffset, endOffset, assumeRelative, null);
}

MinuteFinderParse parseBackupMinuteFinderOutput(String raw, double startOffset, double endOffset, bool assumeRelative, List<BackupPartSpec> parts) {
  return parseFinderGeneric(raw, startOffset, endOffset, assumeRelative, parts);
}
