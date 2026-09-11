import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/chunk.dart';
import '../models/scan.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

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

class RescanResult {
  final bool found;
  final double? movieStart;
  final double? movieEnd;
  final String rawText;
  final String model;
  final int? tokensUsed;

  RescanResult({
    required this.found,
    this.movieStart,
    this.movieEnd,
    required this.rawText,
    required this.model,
    this.tokensUsed,
  });
}

class MinuteFinderWindowResult {
  final String rawText;
  final List<int> matchMinutes;
  final List<int> possibleMinutes;
  final String verdict;
  final int? tokensUsed;

  MinuteFinderWindowResult({
    required this.rawText,
    required this.matchMinutes,
    required this.possibleMinutes,
    required this.verdict,
    this.tokensUsed,
  });
}

class GeminiService {
  GenerativeModel? _model;
  String? _apiKey;
  String _selectedModel = AppConstants.defaultModel;

  // ===========================================================================
  // 1. CHUNK MAP PROMPT (100% Verbatim from lib/gemini.ts)
  // ===========================================================================
  static const String CHUNK_MAP_PROMPT = """You are a forensic video analyst. You are given TWO videos:
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

Poore answer me sirf HISSA 1 aur HISSA 2 do, aur kuch nahi.""";

  // ===========================================================================
  // 2. CHUNK MAP SANITIZED PROMPT (Fallback from lib/gemini.ts)
  // ===========================================================================
  static const String CHUNK_MAP_SANITIZED_PROMPT = """You are an automated visual frame-level timestamp alignment system. You are given TWO silent video streams at 24 fps:
- Video 1: Reference clip stream.
- Video 2: Search segment stream (00:00.000 to ~01:00.000 local clock).

Task: Pure geometric & visual frame alignment only. Do not generate semantic narrative interpretations or conversational text. Output strictly raw timestamp pairs.

Structure your answer in two sections:

=====================
HISSA 1 — SHORT VIDEO TIME MAP
=====================
Break Video 1 into visual sub-intervals:
mm:ss.mmm - mm:ss.mmm (startFrame-endFrame frames): Visual segment <index>

=====================
HISSA 2 — MOVIE MAP TIME
=====================
For each segment from HISSA 1, locate corresponding visual frames in Video 2:
Short mm:ss.mmm - mm:ss.mmm --> Movie mm:ss.mmm - mm:ss.mmm (startFrame-endFrame frames)
If not present:
Short mm:ss.mmm - mm:ss.mmm --> NOT FOUND — not present in this chunk

Only output HISSA 1 and HISSA 2.""";

  // ===========================================================================
  // 3. MINUTE FINDER WINDOW PROMPT (100% Verbatim from lib/gemini.ts)
  // ===========================================================================
  static const String MINUTE_FINDER_PROMPT = """You are a forensic video analyst. You are given TWO videos:
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

Poore answer me sirf HISSA 1, HISSA 2 aur HISSA 3 do, aur kuch nahi.""";

  // ===========================================================================
  // 4. BACKUP MINUTE FINDER PROMPT (100% Verbatim from lib/gemini.ts)
  // ===========================================================================
  static const String BACKUP_MINUTE_FINDER_PROMPT = """You are a forensic video analyst doing a SECOND, FOCUSED search. You are given TWO videos:
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
- Har PART ka TYPE tag do: MOVIE-FOOTAGE / TEXT-CARD / LOGO-INTRO-OUTRO / NON-MOVIE.
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

Poore answer me sirf HISSA 1, HISSA 2 aur HISSA 3 do, aur kuch nahi.""";

  // ===========================================================================
  // 5. 24FPS SINGLE VERIFIER PROMPT (100% Verbatim from lib/gemini.ts)
  // ===========================================================================
  static const String VERIFY_PROMPT = """You are a forensic video verifier. You are given TWO very short clips. Both are exactly 24 fps — compare them frame by frame at 24 fps precision.

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
REASON: <ek chhoti line Hinglish me — Step 2 ke concrete evidence ke saath>""";

  // ===========================================================================
  // 6. 24FPS RESCAN PROMPT (100% Verbatim from lib/gemini.ts)
  // ===========================================================================
  static const String RESCAN_PROMPT = """You are a forensic video analyst. You are given TWO videos:
- Video 1: ek chhota TARGET SEGMENT jo ek SHORT VIDEO se kata gaya hai.
- Video 2: ek ONE-MINUTE CHUNK jo original movie se kata gaya hai.

Both videos are exactly 24 fps. Analyze them frame by frame at 24 fps precision.

Respond in Hinglish (Hindi written in Latin script). Spoken dialogue must always be QUOTED VERBATIM in its original language.

Your answer has exactly TWO parts:

=====================
HISSA 1 — TARGET SEGMENT TIME MAP
=====================
Watch Video 1 from start to finish and break it into small, fine-grained segments:
- Har segment chhota hona chahiye — zyada tar 1 second ya usse kam. Ek continuous shot ko bhi chhote sub-segments me todo.
- Har line ka format:
  mm:ss.mmm - mm:ss.mmm (startFrame-endFrame frames): <SHORT description, max 10-12 words; agar koi bolta hai to sirf exact quoted words>
- Frame numbers = timestamp x 24 (24 fps). Timestamps millisecond precision me.
- Dialogue sabse strong fingerprint hai — kabhi summarize mat karo, hamesha exact words quote karo.

=====================
HISSA 2 — MOVIE CHUNK ME HUNT
=====================
Ab poora Video 2 shuru se aakhir tak frame-by-frame scan karke EXACT wahi footage dhundho jo Video 1 ka target hai (same recording, frame for frame — sirf similar scene nahi).

SEARCH STRATEGY (do-pass method — isi tarah dhundho):
- PASS 1 (LOCATE): Poora Video 2 shuru se aakhir tak scan karo aur har wo jagah note karo jahan target se milta-julta kuch dikhe — same location, same actors, ya (sabse strong) Video 1 ka DIALOGUE audio me sunai de. Dialogue sabse tez locator hai: pehle audio me exact words dhundho, phir us position ke frames dekho. Agar prompt me HINT diya gaya hai to sabse pehle HINT region check karo, phir bhi poora video scan karo.
- PASS 2 (CONFIRM + ALIGN): Har candidate location par frames ko Video 1 ke frames se side-by-side compare karo. Jo location confirm ho, wahan EXACT start/end boundaries frame-by-frame precision se set karo — START-FRAME ANCHOR method use karo: Video 1 ke TARGET ka sabse pehla distinct frame/visual event pehchano (e.g. "haath uthta hai", "cut to close-up", "pehla word bolna shuru"), Video 2 me EXACTLY wahi frame dhundho aur window ka start wahan set karo. End boundary bhi isi tarah aakhri distinct frame se align karo. Window ka pehla frame Video 1 ke pehle frame se align ho, aakhri frame aakhri se.

STRICT RULES:
1. Poora Video 2 shuru se aakhir tak scan karo. Koi shortcut nahi. Ek match milne ke baad bhi baaki video check karo — agar wahi footage do jagah ho to BEST frame-aligned window choose karo.
2. Matched window ki duration EXACTLY Video 1 ke target ki duration ke barabar honi chahiye — na kam, na zyada. EK EXCEPTION: agar target ka footage Video 2 ke bilkul START ya END par CUT ho jata hai (chunk boundary), to jitna hissa Video 2 me maujood hai wahi report karo — window chhoti hogi, ye valid hai.
3. Movie timestamps Video 2 ki APNI clock se aane chahiye (00:00.000 se ~01:00.000) — frames ko actually dekh kar. Video 1 ke timestamps copy karke daalna FORBIDDEN hai.
4. NO EXTRAPOLATION / NO GUESSING (CRITICAL): Kisi bhi formula, offset, ya andaze se timestamp banana STRICTLY FORBIDDEN hai. Sirf wahi window report karo jiske frames tumne Video 2 me khud dekhe aur verify kiye hain.
5. DIALOGUE AUDIO VERIFICATION: Agar Video 1 me koi dialogue hai, to matched window me WAHI EXACT dialogue Video 2 ke audio me us position par actually SUNAI dena chahiye. Words sunai nahi dete = match INVALID — NOT FOUND likho.
6. SIMILAR IS NOT SAME: same actors, same location, same costume par different moment ya different take = NOT FOUND.
7. QUALITY DIFFERENCE IS NOT DIFFERENT: crop, resize, zoom, letterbox/black bars, aspect-ratio change, compression, blur, color-grade, brightness, watermark, text-overlay, subtitles, added music, original audio replaced/muted, duplicate/dropped frames, mirrored image — ye sab IGNORE karo. Underlying footage same hai to wo MATCH hai. In wajahon se match reject karna FORBIDDEN hai.
7b. SPEED TOLERANCE: short video ka footage thoda speed-up/slow-down ho sakta hai (~10-15%) — isliye Video 2 me matched window ki duration target se thodi alag ho sakti hai. Actions ka ORDER aur CONTENT same hai to wo MATCH hai; boundaries frames se align karo, duration ke chhote antar se reject mat karo.
8. NOT FOUND: Agar target Video 2 me sach me NAHI hai, to saaf mana kar do. Zabardasti match banana false positive hai, jo miss karne se bahut zyada bura hai. Lekin NOT FOUND likhne se PEHLE confirm karo ki tumne PASS 1 me poora video (audio samet) scan kiya hai — jaldi me aadha video dekh kar NOT FOUND dena bhi utni hi badi galti hai.
9. FINAL SELF-CHECK: Answer dene se pehle apna MATCH dobara verify karo — (a) kya window ke frames aur audio sach me Video 1 ke target se frame-for-frame match karte hain? (b) kya start/end boundaries frame-accurate hain (aage-piche shift to nahi)? Agar frame evidence nahi hai, to NOT FOUND me badlo.

HISSA 2 ke end me aakhri line EXACTLY is format me do (Video 2 ki apni clock par):
MATCH: mm:ss.mmm - mm:ss.mmm
ya
NOT FOUND — <chhota reason>

Poore answer me sirf HISSA 1 aur HISSA 2 do, aur kuch nahi.""";

  // ===========================================================================
  // 7. 24FPS BATCH VERIFIER PROMPT (100% Verbatim from lib/batch-verifier-prompt.ts)
  // ===========================================================================
  static String buildBatchVerifierPrompt(List<Map<String, dynamic>> parts) {
    final partLines = parts.map((p) {
      final partIndex = p['partIndex'];
      final localStart = Formatters.formatDuration(p['localStart']);
      final localEnd = Formatters.formatDuration(p['localEnd']);
      final shortStart = Formatters.formatDuration(p['shortStart']);
      final shortEnd = Formatters.formatDuration(p['shortEnd']);
      final movieStart = Formatters.formatDuration(p['movieStart']);
      final movieEnd = Formatters.formatDuration(p['movieEnd']);
      final duration = (p['duration'] as double).toStringAsFixed(3);
      return 'PART $partIndex: Stitched Local [$localStart - $localEnd] | Short Original [$shortStart - $shortEnd] <==> Movie Original [$movieStart - $movieEnd] (Duration: ${duration}s)';
    }).join('\n');

    return """You are an ULTRA-STRICT, ADVERSARIAL FORENSIC VIDEO AUDITOR.
Your mandate is to ELIMINATE ALL FALSE POSITIVES with zero leniency.
You are comparing TWO synchronized 24 FPS stitched video streams:
- Video 1: Stitched SHORT VIDEO / REEL clips (Vertical 9:16 format, 24 FPS CFR).
- Video 2: Stitched CANDIDATE ORIGINAL MOVIE clips (Widescreen 16:9 format, 24 FPS CFR).

Both streams are stitched frame-accurately at 24 FPS to an identical local timeline.

=========================================
🚨 CRITICAL MANDATE: AVOID FALSE POSITIVES AT ALL COSTS
=========================================
- A FALSE POSITIVE (approving a wrong clip) CORRUPTS THE ENTIRE EXPORT.
- A REJECTION is safe: any rejected clip automatically triggers a full-chunk rescan to find the true match.
- If you have even a 1% doubt or if timing is offset by even 0.25 seconds, YOU MUST REJECT.
- Default to REJECTED unless the visual evidence is 100% indisputable.

=========================================
🔇 AUDIO RULE: 100% PURE VISUAL ANALYSIS (IGNORE AUDIO)
=========================================
- Video 1 (Short) contains third-party voiceover / background music / external narration.
- DO NOT listen to audio or attempt lip-syncing.
- Evaluate SOLELY based on visual pixel footage at 24 FPS.

=========================================
📐 CROPPING & SPATIAL GEOMETRY (9:16 CROP OF 16:9)
=========================================
- Video 1 is a 9:16 vertical crop of Video 2 (16:9 widescreen).
- The crop may be positioned on the Left, Center, Right, or dynamically panning/zoomed.
- Your task: Verify that the visible content in Video 1 is the EXACT SAME SPATIAL REGION of Video 2 at that EXACT SUB-SECOND MOMENT.

=========================================
⚠️ THE "SAME SCENE / WRONG SECOND" TRAP (THE #1 SOURCE OF ERRORS)
=========================================
Actors stay in the same room wearing the same clothes for 3–5 minutes.
Search models often return a clip from the SAME SCENE but 5, 10, or 30 seconds away from the true moment!
- SAME ACTOR + SAME CLOTHES + SAME ROOM IS NOT A MATCH!
- You MUST verify the EXACT PHYSICAL MICRO-ACTION occurring at each fraction of a second.

=========================================
TIMELINE PART MAP (${parts.length} PAIRED SEGMENTS)
=========================================
$partLines

=========================================
STRICT 6-POINT FORENSIC VERIFICATION CRITERIA
For EACH part, check:
=========================================
1. MICRO-MOTION & TRAJECTORY SYNCHRONIZATION:
   - Arms, hands, fingers: exact angle of movement, speed, and extension.
   - Body posture: exact degree of lean, sitting vs rising, spine curvature.
   - Head & gaze: exact direction of turn, tilt angle, eye movement.

2. PROPS & OBJECT STATES:
   - Exact prop held, its orientation, and interaction state (cup at lips vs on table, phone in pocket vs in hand).

3. CHRONOMETRIC TIMING PRECISION:
   - If an event happens at +0.3s in Video 1, it MUST happen at +0.3s in Video 2.

4. FACIAL EXPRESSIONS & MICRO-FEATURES:
   - Mouth shapes, eyebrow position, smile/frown tension, blink timing.

5. LIGHTING, SHADOWS & BACKGROUND DETAILS:
   - Moving shadows, background objects, secondary extras passing by.

6. CUT / SCENE TRANSITION BOUNDARIES:
   - If there is a camera cut, it must happen at the exact same sub-second frame in both.

=========================================
DECISION THRESHOLDS:
=========================================
- "CONFIRMED": ONLY when you are 100% positive that EVERY frame of Video 1 is the exact spatial crop of Video 2 at that exact fraction of a second. Confidence MUST BE >= 0.92.
- "REJECTED": If there is ANY discrepancy in action, posture, prop, or timing. rescanRequired: true.

=========================================
REQUIRED OUTPUT FORMAT (JSON ONLY)
=========================================
Respond with a single valid JSON object containing an array of verdicts for all ${parts.length} parts:

```json
{
  "verdicts": [
    {
      "partIndex": 1,
      "verdict": "CONFIRMED",
      "confidence": 0.98,
      "cropPosition": "Center 9:16 crop",
      "visualAnchorProof": "Exact micro-action match",
      "reason": "Indisputable frame-accurate visual match. All micro-actions align 1:1.",
      "rescanRequired": false
    }
  ]
}
```

Provide a verdict for EVERY single PART from 1 to ${parts.length}.""";
  }

  void configure(String apiKey, {String? modelName}) {
    _apiKey = apiKey;
    _selectedModel = modelName ?? AppConstants.defaultModel;
    _model = GenerativeModel(
      model: _selectedModel,
      apiKey: _apiKey!,
      generationConfig: GenerationConfig(
        temperature: 0,
        maxOutputTokens: 8192,
      ),
    );
  }

  bool get isConfigured => _apiKey != null && _apiKey!.trim().isNotEmpty;

  static String buildMinuteFinderPrompt(double startOffsetSec, double endOffsetSec) {
    return MINUTE_FINDER_PROMPT
        .replaceAll('{{WINDOW_START}}', Formatters.formatDuration(startOffsetSec))
        .replaceAll('{{WINDOW_END}}', Formatters.formatDuration(endOffsetSec));
  }

  static String buildBackupMinuteFinderPrompt(
    double startOffsetSec,
    double endOffsetSec,
    int clipFps,
    String partMap,
    String foundSummary,
  ) {
    return BACKUP_MINUTE_FINDER_PROMPT
        .replaceAll('{{WINDOW_START}}', Formatters.formatDuration(startOffsetSec))
        .replaceAll('{{WINDOW_END}}', Formatters.formatDuration(endOffsetSec))
        .replaceAll('{{CLIP_FPS}}', clipFps.toString())
        .replaceAll('{{PART_MAP}}', partMap)
        .replaceAll('{{FOUND_SUMMARY}}', foundSummary.isEmpty ? 'NONE' : foundSummary);
  }

  /// Run 24fps chunk mapping between short video and one-minute movie chunk
  Future<ChunkMapResult> mapChunk({
    required String shortPath,
    required String chunkPath,
    required int chunkIndex,
    required double chunkOffsetSeconds,
  }) async {
    if (_model == null || _apiKey == null) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API key is not configured.');
    }

    final shortBytes = await File(shortPath).readAsBytes();
    final chunkBytes = await File(chunkPath).readAsBytes();

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

  /// Run 20-min window prescan request with MINUTE_FINDER_PROMPT
  Future<MinuteFinderWindowResult> runMinuteFinderWindow({
    required String shortPath,
    required String movieWindowPath,
    required double startSec,
    required double endSec,
  }) async {
    if (_model == null || _apiKey == null) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API not configured');
    }

    final shortBytes = await File(shortPath).readAsBytes();
    final windowBytes = await File(movieWindowPath).readAsBytes();
    final prompt = buildMinuteFinderPrompt(startSec, endSec);

    final content = [
      Content.multi([
        DataPart('video/mp4', shortBytes),
        DataPart('video/mp4', windowBytes),
        TextPart(prompt),
      ])
    ];

    try {
      final response = await _model!.generateContent(content);
      final text = response.text ?? '';
      final parsed = parseMinuteFinderOutput(text);

      return MinuteFinderWindowResult(
        rawText: text,
        matchMinutes: parsed.matchMinutes,
        possibleMinutes: parsed.possibleMinutes,
        verdict: parsed.verdict,
        tokensUsed: response.usageMetadata?.totalTokenCount,
      );
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException(_classifyError(e), e.toString());
    }
  }

  /// Run verification on short clip vs extracted movie candidate clip (24fps frame-accurate comparison)
  Future<VerifyResult> verifyCandidate({
    required String shortClipPath,
    required String movieClipPath,
    String? verifyModel,
  }) async {
    if (_apiKey == null || _apiKey!.trim().isEmpty) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API not configured');
    }

    final targetModel = verifyModel ?? AppConstants.defaultVerifyModel;
    final verifier = GenerativeModel(
      model: targetModel,
      apiKey: _apiKey!,
      generationConfig: GenerationConfig(
        temperature: 0,
        maxOutputTokens: 8192,
      ),
    );

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
      final response = await verifier.generateContent(content);
      final text = response.text ?? '';
      final parsed = parseVerdict(text);

      return VerifyResult(
        same: parsed.same,
        reason: parsed.reason,
        rawText: text,
      );
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException(_classifyError(e), e.toString());
    }
  }

  /// Run Rescan request on a target short segment vs a full 1-minute movie chunk (24fps)
  Future<RescanResult> rescanSegment({
    required String targetSegmentPath,
    required String chunkMoviePath,
    required double chunkOffsetSeconds,
    String? rescanModel,
  }) async {
    if (_apiKey == null || _apiKey!.trim().isEmpty) {
      throw GeminiException(GeminiErrorKind.invalidKey, 'Gemini API not configured');
    }

    final targetModel = rescanModel ?? AppConstants.defaultRescanModel;
    final rescanGenerator = GenerativeModel(
      model: targetModel,
      apiKey: _apiKey!,
      generationConfig: GenerationConfig(
        temperature: 0,
        maxOutputTokens: 65536,
      ),
    );

    final segmentBytes = await File(targetSegmentPath).readAsBytes();
    final chunkBytes = await File(chunkMoviePath).readAsBytes();

    final content = [
      Content.multi([
        DataPart('video/mp4', segmentBytes),
        DataPart('video/mp4', chunkBytes),
        TextPart(RESCAN_PROMPT),
      ])
    ];

    try {
      final response = await rescanGenerator.generateContent(content);
      final text = response.text ?? '';
      final match = parseRescanMatch(text, chunkOffsetSeconds: chunkOffsetSeconds);

      return RescanResult(
        found: match != null,
        movieStart: match?.start,
        movieEnd: match?.end,
        rawText: text,
        model: targetModel,
        tokensUsed: response.usageMetadata?.totalTokenCount,
      );
    } catch (e) {
      // If primary rescan model fails with quota/rate-limit, attempt fallback to backup pool
      if (rescanModel == null && AppConstants.rescanBackupPool.isNotEmpty) {
        final fallbackModel = AppConstants.rescanBackupPool.first.id;
        return rescanSegment(
          targetSegmentPath: targetSegmentPath,
          chunkMoviePath: chunkMoviePath,
          chunkOffsetSeconds: chunkOffsetSeconds,
          rescanModel: fallbackModel,
        );
      }
      if (e is GeminiException) rethrow;
      throw GeminiException(_classifyError(e), e.toString());
    }
  }

  /// Parse VERDICT: SAME / DIFFERENT from verification output
  ({bool same, String reason}) parseVerdict(String raw) {
    bool same = false;
    String reason = '';

    final verdictMatch = RegExp(r'VERDICT\s*:\s*(SAME|DIFFERENT)', caseSensitive: false).firstMatch(raw);
    if (verdictMatch != null) {
      same = verdictMatch.group(1)!.toUpperCase() == 'SAME';
    } else {
      same = raw.contains('"verdict": "CONFIRMED"') || raw.contains('CONFIRMED');
    }

    final reasonMatch = RegExp(r'REASON\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    if (reasonMatch != null) {
      reason = reasonMatch.group(1)!.trim();
    } else {
      reason = same ? 'Confirmed 1:1 micro-action anchor match' : 'Rejected temporal or micro-action mismatch';
    }

    return (same: same, reason: reason);
  }

  /// Parse MATCH: mm:ss.mmm - mm:ss.mmm from RESCAN HISSA 2 output
  ({double start, double end})? parseRescanMatch(String raw, {required double chunkOffsetSeconds}) {
    final matchLine = RegExp(
      r'MATCH\s*:\s*((?:\d+:)?\d+:\d+(?:\.\d+)?)\s*(?:-|–|to)\s*((?:\d+:)?\d+:\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(raw);

    if (matchLine != null) {
      final start = _parseTimestamp(matchLine.group(1)!);
      final end = _parseTimestamp(matchLine.group(2)!);
      if (start != null && end != null && end > start) {
        return (start: chunkOffsetSeconds + start, end: chunkOffsetSeconds + end);
      }
    }
    return null;
  }

  /// Parse matches from HISSA 2 lines in model output
  List<ChunkMatch> parseMatches(
    String raw, {
    required int chunkIndex,
    required double chunkOffsetSeconds,
    required String modelName,
  }) {
    final matches = <ChunkMatch>[];
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

  /// Parse MATCH MINUTES, POSSIBLE MINUTES, WINDOW VERDICT from HISSA 3 in Minute Finder output
  ({List<int> matchMinutes, List<int> possibleMinutes, String verdict}) parseMinuteFinderOutput(String raw) {
    final matchMinutes = <int>[];
    final possibleMinutes = <int>[];
    String verdict = 'NOT IN THIS WINDOW';

    final matchLine = RegExp(r'MATCH MINUTES\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    if (matchLine != null) {
      final val = matchLine.group(1)!.trim();
      if (val.toUpperCase() != 'NONE') {
        for (final m in RegExp(r'\b\d+\b').allMatches(val)) {
          final n = int.tryParse(m.group(0)!);
          if (n != null && !matchMinutes.contains(n)) matchMinutes.add(n);
        }
      }
    }

    final possibleLine = RegExp(r'POSSIBLE MINUTES\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    if (possibleLine != null) {
      final val = possibleLine.group(1)!.trim();
      if (val.toUpperCase() != 'NONE') {
        for (final m in RegExp(r'\b\d+\b').allMatches(val)) {
          final n = int.tryParse(m.group(0)!);
          if (n != null && !possibleMinutes.contains(n)) possibleMinutes.add(n);
        }
      }
    }

    final verdictLine = RegExp(r'WINDOW VERDICT\s*:\s*([^\n]+)', caseSensitive: false).firstMatch(raw);
    if (verdictLine != null) {
      verdict = verdictLine.group(1)!.trim();
    } else if (matchMinutes.isNotEmpty) {
      verdict = 'FOUND';
    } else if (possibleMinutes.isNotEmpty) {
      verdict = 'POSSIBLE ONLY';
    }

    return (matchMinutes: matchMinutes, possibleMinutes: possibleMinutes, verdict: verdict);
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
