import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// 1:1 Port of lib/session.ts
/// Signed stateless session tokens — HMAC-SHA256 with timestamp expiry.

const String SESSION_COOKIE = 'cmt_session';
const int SESSION_DAYS = 7;

class SessionUser {
  final String username;
  final String role; // 'admin' | 'user'

  const SessionUser({required this.username, required this.role});

  Map<String, dynamic> toJson() => {'username': username, 'role': role};

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        username: json['username'] ?? '',
        role: json['role'] ?? 'user',
      );
}

class SessionService {
  static final String _secret = (() {
    final s = Platform.environment['SESSION_SECRET'];
    if (s != null && s.length >= 16) return s;
    return 'cmt-dev-secret-mobile-preview-fallback';
  })();

  static String _hmac(String payload) {
    final key = utf8.encode(_secret);
    final bytes = utf8.encode(payload);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Sign session for user
  static String signSession(SessionUser user) {
    final payloadMap = {
      'u': user.username,
      'r': user.role,
      'exp': DateTime.now().millisecondsSinceEpoch + SESSION_DAYS * 24 * 60 * 60 * 1000,
    };
    final payload = base64Url.encode(utf8.encode(jsonEncode(payloadMap))).replaceAll('=', '');
    final signature = _hmac(payload);
    return '$payload.$signature';
  }

  /// Verify session token
  static SessionUser? verifySessionToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final dot = token.lastIndexOf('.');
    if (dot <= 0) return null;

    final payload = token.substring(0, dot);
    final sig = token.substring(dot + 1);
    final expectedSig = _hmac(payload);

    if (sig != expectedSig) return null;

    try {
      final normalized = base64.normalize(payload);
      final decodedJson = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decodedJson) as Map<String, dynamic>;

      final exp = data['exp'] as int?;
      if (exp == null || exp < DateTime.now().millisecondsSinceEpoch) return null;

      final u = data['u'] as String?;
      final r = data['r'] as String?;
      if (u == null || (r != 'admin' && r != 'user')) return null;

      return SessionUser(username: u, role: r);
    } catch (_) {
      return null;
    }
  }
}
