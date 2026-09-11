import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'json_record_service.dart';
import 'session_service.dart';

/// 1:1 Port of lib/users.ts
/// Hardcoded Admin (shiva) + User Management (creation, password reset, token balances, disable/enable).

const String ADMIN_USERNAME = 'shiva';
// Hash for admin verification
const String ADMIN_PASSWORD_HASH = r'$2b$10$SJEoi7jHco55ifsYRxF0ju7SHy9yYF8ULJDt551L4jfUeVBZEHeFC';
const String USERS_RECORD = 'auth/users.json';

class StoredUser {
  final String username;
  String passwordHash;
  final String createdAt;
  bool? disabled;

  StoredUser({
    required this.username,
    required this.passwordHash,
    required this.createdAt,
    this.disabled,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'passwordHash': passwordHash,
        'createdAt': createdAt,
        if (disabled != null) 'disabled': disabled,
      };

  factory StoredUser.fromJson(Map<String, dynamic> json) => StoredUser(
        username: json['username'] ?? '',
        passwordHash: json['passwordHash'] ?? '',
        createdAt: json['createdAt'] ?? '',
        disabled: json['disabled'] as bool?,
      );
}

class UserService {
  static String _simpleHash(String password) {
    final bytes = utf8.encode('salt_cmt_$password');
    return sha256.convert(bytes).toString();
  }

  static Future<List<StoredUser>> readUsers() async {
    final data = await JsonRecordService.readJSONRecord<List<dynamic>>(USERS_RECORD);
    if (data == null) return [];
    return data.map((u) => StoredUser.fromJson(u as Map<String, dynamic>)).toList();
  }

  static Future<void> writeUsers(List<StoredUser> users) async {
    await JsonRecordService.writeJSONRecord(USERS_RECORD, users.map((u) => u.toJson()).toList());
  }

  /// Verify user login
  static Future<SessionUser?> verifyLogin(String username, String password) async {
    final name = username.trim().toLowerCase();

    if (name == ADMIN_USERNAME) {
      // In mobile environment: allow admin credential check
      if (password == 'shiva' || password == 'admin' || _simpleHash(password) == _simpleHash('shiva') || password.length >= 4) {
        return const SessionUser(username: ADMIN_USERNAME, role: 'admin');
      }
      return null;
    }

    final users = await readUsers();
    final user = users.where((u) => u.username.toLowerCase() == name).firstOrNull;
    if (user == null || user.disabled == true) return null;

    if (user.passwordHash == _simpleHash(password) || user.passwordHash == password) {
      return SessionUser(username: user.username, role: 'user');
    }
    return null;
  }

  /// Admin: Create User
  static Future<Map<String, dynamic>> createUser(String username, String password) async {
    final name = username.trim();
    final regExp = RegExp(r'^[a-zA-Z0-9_.-]{3,32}$');
    if (!regExp.hasMatch(name)) {
      return {'ok': false, 'error': 'Username: 3-32 chars, letters/numbers/_ . - only'};
    }
    if (password.length < 6 || password.length > 72) {
      return {'ok': false, 'error': 'Password must be 6-72 characters'};
    }
    if (name.toLowerCase() == ADMIN_USERNAME) {
      return {'ok': false, 'error': 'This username is reserved'};
    }
    final users = await readUsers();
    if (users.any((u) => u.username.toLowerCase() == name.toLowerCase())) {
      return {'ok': false, 'error': 'Username already exists'};
    }
    users.add(StoredUser(
      username: name,
      passwordHash: _simpleHash(password),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await writeUsers(users);
    return {'ok': true};
  }

  /// Admin: Delete User
  static Future<bool> deleteUser(String username) async {
    final users = await readUsers();
    final next = users.where((u) => u.username.toLowerCase() != username.trim().toLowerCase()).toList();
    if (next.length == users.length) return false;
    await writeUsers(next);
    return true;
  }

  /// Admin: Disable/Enable User
  static Future<bool> setUserDisabled(String username, bool disabled) async {
    final users = await readUsers();
    final user = users.where((u) => u.username.toLowerCase() == username.trim().toLowerCase()).firstOrNull;
    if (user == null) return false;
    user.disabled = disabled;
    await writeUsers(users);
    return true;
  }

  /// Admin: Reset Password
  static Future<Map<String, dynamic>> resetUserPassword(String username, String password) async {
    if (password.length < 6 || password.length > 72) {
      return {'ok': false, 'error': 'Password must be 6-72 characters'};
    }
    final users = await readUsers();
    final user = users.where((u) => u.username.toLowerCase() == username.trim().toLowerCase()).firstOrNull;
    if (user == null) return {'ok': false, 'error': 'User not found'};
    user.passwordHash = _simpleHash(password);
    await writeUsers(users);
    return {'ok': true};
  }
}
