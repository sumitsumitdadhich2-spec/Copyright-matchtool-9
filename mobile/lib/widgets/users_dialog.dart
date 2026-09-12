import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/auth_api.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/auth/users-dialog.tsx
/// Admin user management dialog (create user, set token balances, reset passwords, toggle disabled, delete user).

class ManagedUserInfo {
  final String username;
  final String createdAt;
  final bool disabled;
  final int tokens;

  ManagedUserInfo({
    required this.username,
    required this.createdAt,
    required this.disabled,
    required this.tokens,
  });

  factory ManagedUserInfo.fromJson(Map<String, dynamic> json) {
    return ManagedUserInfo(
      username: json['username']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      disabled: json['disabled'] == true,
      tokens: (json['tokens'] as num?)?.toInt() ?? 0,
    );
  }
}

class UsersDialog extends StatefulWidget {
  const UsersDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => const UsersDialog(),
    );
  }

  @override
  State<UsersDialog> createState() => _UsersDialogState();
}

class _UsersDialogState extends State<UsersDialog> {
  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  List<ManagedUserInfo> _users = [];
  bool _isLoading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _loadSessionAndUsers();
  }

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionAndUsers() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _sessionToken = prefs.getString(SESSION_COOKIE);
    await _refreshUsers();
  }

  Future<void> _refreshUsers() async {
    try {
      final res = await AuthApi.getUsers(_sessionToken);
      if (res.statusCode == 200) {
        final list = (res.data['users'] as List<dynamic>?) ?? [];
        if (mounted) {
          setState(() {
            _users = list.map((u) => ManagedUserInfo.fromJson(u as Map<String, dynamic>)).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = res.data['error']?.toString() ?? 'Failed to load users';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading users: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addUser() async {
    final username = _newUsernameController.text.trim();
    final password = _newPasswordController.text;

    if (_busy || username.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final res = await AuthApi.createUser(
        sessionToken: _sessionToken,
        username: username,
        password: password,
      );

      if (res.statusCode == 200 && res.data['ok'] == true) {
        _newUsernameController.clear();
        _newPasswordController.clear();
        _notice = 'User "$username" created — share the ID and password with them.';
        await _refreshUsers();
      } else {
        _error = res.data['error']?.toString() ?? 'Failed to create user';
      }
    } catch (e) {
      _error = 'Network error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setTokens(ManagedUserInfo user) async {
    final controller = TextEditingController(text: user.tokens.toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Text(
          'Set Tokens for ${user.username}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '100 tokens = 1 scan',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tokens amount',
                hintText: 'e.g. 500',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final amount = int.tryParse(controller.text.trim());
      if (amount == null || amount < 0) {
        setState(() => _error = 'Valid token amount daalo (0 ya usse zyada)');
        return;
      }

      setState(() => _busy = true);
      try {
        final res = await AuthApi.patchUser(
          sessionToken: _sessionToken,
          username: user.username,
          tokens: amount,
        );
        if (res.statusCode == 200 && res.data['ok'] == true) {
          _notice = '"${user.username}" ke tokens ab $amount hain.';
          await _refreshUsers();
        } else {
          _error = res.data['error']?.toString() ?? 'Failed to update tokens';
        }
      } catch (e) {
        _error = 'Error: $e';
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _resetPassword(ManagedUserInfo user) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Text(
          'Reset Password for "${user.username}"',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textForeground),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New password (min 6 chars)',
            hintText: 'Enter new password',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.isNotEmpty) {
      setState(() => _busy = true);
      try {
        final res = await AuthApi.patchUser(
          sessionToken: _sessionToken,
          username: user.username,
          password: controller.text,
        );
        if (res.statusCode == 200 && res.data['ok'] == true) {
          _notice = 'Password updated for "${user.username}".';
        } else {
          _error = res.data['error']?.toString() ?? 'Failed to reset password';
        }
      } catch (e) {
        _error = 'Error: $e';
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggleDisabled(ManagedUserInfo user) async {
    setState(() => _busy = true);
    try {
      final res = await AuthApi.patchUser(
        sessionToken: _sessionToken,
        username: user.username,
        disabled: !user.disabled,
      );
      if (res.statusCode == 200 && res.data['ok'] == true) {
        _notice = 'User "${user.username}" ${user.disabled ? "enabled" : "disabled"}.';
        await _refreshUsers();
      } else {
        _error = res.data['error']?.toString() ?? 'Failed to toggle user status';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeUser(ManagedUserInfo user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text('Delete User?'),
        content: Text(
          'Delete user "${user.username}"? They will lose access permanently.',
          style: const TextStyle(fontSize: 14, color: AppTheme.textForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.destructive),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _busy = true);
      try {
        final res = await AuthApi.deleteUser(
          sessionToken: _sessionToken,
          username: user.username,
        );
        if (res.statusCode == 200 && res.data['ok'] == true) {
          _notice = 'User "${user.username}" deleted.';
          await _refreshUsers();
        } else {
          _error = res.data['error']?.toString() ?? 'Failed to delete user';
        }
      } catch (e) {
        _error = 'Error: $e';
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.people_outline, size: 20, color: AppTheme.primary),
                    SizedBox(width: 8),
                    Text(
                      'Manage users',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textForeground,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Form: Create new user ID
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create new user ID',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newUsernameController,
                          autocorrect: false,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Username',
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _newPasswordController,
                          obscureText: true,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Password (min 6)',
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _busy ? null : _addUser,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.add, size: 16),
                                  SizedBox(width: 4),
                                  Text('Create', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Error & Notice alerts
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.destructive.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.destructive.withOpacity(0.4)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.destructive),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_notice != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                ),
                child: Text(
                  _notice!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // User count label
            Row(
              children: [
                Text(
                  'USERS (${_users.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppTheme.textMuted,
                  ),
                ),
                if (_isLoading) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Users list
            Expanded(
              child: _isLoading && _users.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? Center(
                          child: Text(
                            'No users yet — create the first ID above.',
                            style: TextStyle(fontSize: 13, color: AppTheme.textMuted.withOpacity(0.8)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final u = _users[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              u.username,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textForeground,
                                              ),
                                            ),
                                            if (u.disabled) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.destructive.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: AppTheme.destructive.withOpacity(0.3)),
                                                ),
                                                child: const Text(
                                                  'DISABLED',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.destructive,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Created ${u.createdAt.length >= 10 ? u.createdAt.substring(0, 10) : u.createdAt}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.warning.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.monetization_on_outlined, size: 12, color: AppTheme.warning),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${u.tokens} tokens',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'monospace',
                                                  color: AppTheme.warning,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Action Buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Set tokens
                                      IconButton(
                                        icon: const Icon(Icons.monetization_on_outlined, size: 18, color: AppTheme.warning),
                                        tooltip: 'Set tokens (100 tokens = 1 scan)',
                                        onPressed: _busy ? null : () => _setTokens(u),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                      ),
                                      // Reset password
                                      IconButton(
                                        icon: const Icon(Icons.key_outlined, size: 18, color: AppTheme.textMuted),
                                        tooltip: 'Reset password',
                                        onPressed: _busy ? null : () => _resetPassword(u),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                      ),
                                      // Toggle disabled
                                      IconButton(
                                        icon: Icon(
                                          u.disabled ? Icons.person_add_alt_1_outlined : Icons.person_off_outlined,
                                          size: 18,
                                          color: u.disabled ? AppTheme.success : AppTheme.textMuted,
                                        ),
                                        tooltip: u.disabled ? 'Enable user' : 'Disable user',
                                        onPressed: _busy ? null : () => _toggleDisabled(u),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                      ),
                                      // Delete user
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.destructive),
                                        tooltip: 'Delete user',
                                        onPressed: _busy ? null : () => _removeUser(u),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
