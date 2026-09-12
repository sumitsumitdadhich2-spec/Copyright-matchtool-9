import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/auth_api.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/auth/login-screen.tsx
/// Login screen with Shiva MatchTool branding, lock badge, credentials form & error alert.

class LoginScreen extends StatefulWidget {
  final ValueChanged<SessionUser> onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (_busy || username.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await AuthApi.login(username: username, password: password);
      if (res.statusCode != 200 || res.data['ok'] != true) {
        setState(() {
          _error = res.data['error']?.toString() ?? 'Login failed';
        });
        return;
      }

      final userData = res.data['user'] as Map<String, dynamic>;
      final user = SessionUser.fromJson(userData);

      // Save session token in SharedPreferences
      final token = SessionService.signSession(user);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SESSION_COOKIE, token);

      widget.onLoggedIn(user);
    } catch (e) {
      setState(() {
        _error = 'Network error — try again ($e)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Icon Header
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.document_scanner,
                      color: AppTheme.primaryForeground,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Title
                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textForeground,
                        letterSpacing: -0.3,
                      ),
                      children: [
                        TextSpan(text: 'Shiva '),
                        TextSpan(
                          text: 'MatchTool',
                          style: TextStyle(color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Restricted Access Badge
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.lock_outline, size: 12, color: AppTheme.textMuted),
                      SizedBox(width: 4),
                      Text(
                        'RESTRICTED ACCESS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                          color: AppTheme.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Username field
                const Text(
                  'Username',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _usernameController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textForeground),
                  decoration: const InputDecoration(
                    hintText: 'Enter username',
                    prefixIcon: Icon(Icons.person_outline, size: 18, color: AppTheme.textMuted),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 14),

                // Password field
                const Text(
                  'Password',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textForeground),
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    prefixIcon: const Icon(Icons.key_outlined, size: 18, color: AppTheme.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 14),

                // Error message
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.destructive.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.destructive.withOpacity(0.4)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.destructive,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Sign in Button
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.primaryForeground,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryForeground),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.lock_outline, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Sign in',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
