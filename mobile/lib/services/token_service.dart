import 'json_record_service.dart';

/// 1:1 Port of lib/tokens.ts
/// Per-user token balances — stored in JSON record on local disk + S3.
/// 1 scan = 100 tokens. Admin (shiva) has unlimited tokens.

const int SCAN_TOKEN_COST = 100;
const String TOKENS_RECORD = 'auth/tokens.json';

class TokenService {
  static String _keyFor(String username) {
    return username.trim().toLowerCase();
  }

  static Future<Map<String, int>> _readTokenMap() async {
    final data = await JsonRecordService.readJSONRecord<Map<String, dynamic>>(TOKENS_RECORD);
    if (data == null) return {};
    return data.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  static Future<void> _writeTokenMap(Map<String, int> map) async {
    await JsonRecordService.writeJSONRecord(TOKENS_RECORD, map);
  }

  /// Current token balance for a user (0 if never set)
  static Future<int> getTokenBalance(String username) async {
    final map = await _readTokenMap();
    return map[_keyFor(username)] ?? 0;
  }

  /// Admin: set a user's balance to an exact amount
  static Future<int> setTokenBalance(String username, int amount) async {
    final map = await _readTokenMap();
    final next = [0, amount].reduce((a, b) => a > b ? a : b);
    map[_keyFor(username)] = next;
    await _writeTokenMap(map);
    return next;
  }

  /// Deduct tokens for a scan. Returns new balance, or null if insufficient
  static Future<int?> deductTokens(String username, int amount) async {
    final map = await _readTokenMap();
    final key = _keyFor(username);
    final current = map[key] ?? 0;
    if (current < amount) return null;
    map[key] = current - amount;
    await _writeTokenMap(map);
    return map[key];
  }

  /// Refund tokens (e.g. when scan fails to start)
  static Future<int> refundTokens(String username, int amount) async {
    final map = await _readTokenMap();
    final key = _keyFor(username);
    map[key] = (map[key] ?? 0) + amount;
    await _writeTokenMap(map);
    return map[key]!;
  }

  /// Remove a deleted user's balance entry
  static Future<void> deleteTokenEntry(String username) async {
    final map = await _readTokenMap();
    final key = _keyFor(username);
    if (map.containsKey(key)) {
      map.remove(key);
      await _writeTokenMap(map);
    }
  }

  /// Balances for many users at once
  static Future<Map<String, int>> getTokenBalances(List<String> usernames) async {
    final map = await _readTokenMap();
    final out = <String, int>{};
    for (final u in usernames) {
      out[u] = map[_keyFor(u)] ?? 0;
    }
    return out;
  }
}
