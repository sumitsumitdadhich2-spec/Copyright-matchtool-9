import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/auth_api.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// 1:1 Port of components/auth/auth-gate.tsx
/// Wraps the application, verifying session token with /api/auth/me and gating behind LoginScreen.

class AuthScope extends InheritedWidget {
  final SessionUser user;
  final Future<void> Function() logout;
  final VoidCallback refresh;

  const AuthScope({
    super.key,
    required this.user,
    required this.logout,
    required this.refresh,
    required super.child,
  });

  static AuthScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AuthScope>();
  }

  static AuthScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'AuthScope must be used inside AuthGate');
    return scope!;
  }

  @override
  bool updateShouldNotify(AuthScope oldWidget) {
    return user.username != oldWidget.user.username || user.role != oldWidget.user.role;
  }
}

class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  static AuthScope of(BuildContext context) => AuthScope.of(context);
  static AuthScope? maybeOf(BuildContext context) => AuthScope.maybeOf(context);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  SessionUser? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(SESSION_COOKIE);

      if (token != null && token.isNotEmpty) {
        final res = await AuthApi.me(token);
        if (res.statusCode == 200 && res.data['user'] != null) {
          final u = SessionUser.fromJson(res.data['user'] as Map<String, dynamic>);
          if (mounted) {
            setState(() {
              _user = u;
              _isLoading = false;
            });
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _user = null;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _user = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SESSION_COOKIE);
    await AuthApi.logout();
    if (mounted) {
      setState(() {
        _user = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ),
      );
    }

    if (_user == null) {
      return LoginScreen(
        onLoggedIn: (u) {
          setState(() {
            _user = u;
          });
        },
      );
    }

    return AuthScope(
      user: _user!,
      logout: _logout,
      refresh: _checkSession,
      child: widget.child,
    );
  }
}
