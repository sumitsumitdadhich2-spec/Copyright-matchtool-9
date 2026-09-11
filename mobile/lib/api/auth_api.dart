import '../services/user_service.dart';
import '../services/session_service.dart';
import '../services/token_service.dart';
import '../services/user_keys_service.dart';

/// 1:1 Port of app/api/auth/login, app/api/auth/logout, app/api/auth/me, app/api/auth/users
/// Complete Authentication and User Management Controller

class AuthApiResponse {
  final int statusCode;
  final Map<String, dynamic> data;
  final String? setCookie;

  AuthApiResponse({
    required this.statusCode,
    required this.data,
    this.setCookie,
  });
}

class AuthApi {
  /// POST /api/auth/login
  static Future<AuthApiResponse> login({
    required String? username,
    required String? password,
  }) async {
    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return AuthApiResponse(statusCode: 400, data: {'error': 'Username and password required'});
    }

    final user = await UserService.verifyLogin(username, password);
    if (user == null) {
      return AuthApiResponse(statusCode: 401, data: {'error': 'Invalid username or password'});
    }

    final token = SessionService.signSession(user);
    return AuthApiResponse(
      statusCode: 200,
      data: {'ok': true, 'user': user.toJson()},
      setCookie: '$SESSION_COOKIE=$token; Path=/; HttpOnly; SameSite=None; Secure',
    );
  }

  /// POST /api/auth/logout
  static Future<AuthApiResponse> logout() async {
    return AuthApiResponse(
      statusCode: 200,
      data: {'ok': true},
      setCookie: '$SESSION_COOKIE=; Path=/; HttpOnly; SameSite=None; Secure; Max-Age=0',
    );
  }

  /// GET /api/auth/me
  static Future<AuthApiResponse> me(String? sessionToken) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null) {
      return AuthApiResponse(statusCode: 401, data: {'user': null});
    }
    return AuthApiResponse(statusCode: 200, data: {'user': session.toJson()});
  }

  /// GET /api/auth/users
  static Future<AuthApiResponse> getUsers(String? sessionToken) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null || session.role != 'admin') {
      return AuthApiResponse(statusCode: 403, data: {'error': 'Admin only'});
    }

    final users = await UserService.readUsers();
    final balances = await TokenService.getTokenBalances(users.map((u) => u.username).toList());

    return AuthApiResponse(
      statusCode: 200,
      data: {
        'users': users.map((u) => {
              'username': u.username,
              'createdAt': u.createdAt,
              'disabled': u.disabled == true,
              'tokens': balances[u.username] ?? 0,
            }).toList(),
      },
    );
  }

  /// POST /api/auth/users (Create user)
  static Future<AuthApiResponse> createUser({
    required String? sessionToken,
    required String? username,
    required String? password,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null || session.role != 'admin') {
      return AuthApiResponse(statusCode: 403, data: {'error': 'Admin only'});
    }

    if (username == null || username.isEmpty || password == null || password.isEmpty) {
      return AuthApiResponse(statusCode: 400, data: {'error': 'Username and password required'});
    }

    final result = await UserService.createUser(username, password);
    if (result['ok'] != true) {
      return AuthApiResponse(statusCode: 400, data: {'error': result['error']});
    }
    return AuthApiResponse(statusCode: 200, data: {'ok': true});
  }

  /// PATCH /api/auth/users (Update user / tokens / password / disabled status)
  static Future<AuthApiResponse> patchUser({
    required String? sessionToken,
    required String? username,
    bool? disabled,
    String? password,
    int? tokens,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null || session.role != 'admin') {
      return AuthApiResponse(statusCode: 403, data: {'error': 'Admin only'});
    }

    if (username == null || username.isEmpty) {
      return AuthApiResponse(statusCode: 400, data: {'error': 'Username required'});
    }

    // Set token balance
    if (tokens != null) {
      final users = await UserService.readUsers();
      final exists = users.any((u) => u.username.toLowerCase() == username.trim().toLowerCase());
      if (!exists) return AuthApiResponse(statusCode: 404, data: {'error': 'User not found'});
      final balance = await TokenService.setTokenBalance(username, tokens);
      return AuthApiResponse(statusCode: 200, data: {'ok': true, 'tokens': balance});
    }

    // Reset password
    if (password != null && password.isNotEmpty) {
      final result = await UserService.resetUserPassword(username, password);
      if (result['ok'] != true) {
        return AuthApiResponse(statusCode: 400, data: {'error': result['error']});
      }
      return AuthApiResponse(statusCode: 200, data: {'ok': true});
    }

    // Set disabled
    if (disabled != null) {
      final ok = await UserService.setUserDisabled(username, disabled);
      if (!ok) return AuthApiResponse(statusCode: 404, data: {'error': 'User not found'});
      return AuthApiResponse(statusCode: 200, data: {'ok': true});
    }

    return AuthApiResponse(statusCode: 400, data: {'error': 'Nothing to update'});
  }

  /// DELETE /api/auth/users (Delete user)
  static Future<AuthApiResponse> deleteUser({
    required String? sessionToken,
    required String? username,
  }) async {
    final session = SessionService.verifySessionToken(sessionToken);
    if (session == null || session.role != 'admin') {
      return AuthApiResponse(statusCode: 403, data: {'error': 'Admin only'});
    }

    if (username == null || username.isEmpty) {
      return AuthApiResponse(statusCode: 400, data: {'error': 'Username required'});
    }

    final ok = await UserService.deleteUser(username);
    if (!ok) return AuthApiResponse(statusCode: 404, data: {'error': 'User not found'});

    // Wipe user's private keys and tokens
    await UserKeysService.deleteUserKeys(username);
    await TokenService.deleteTokenEntry(username);

    return AuthApiResponse(statusCode: 200, data: {'ok': true});
  }
}
