import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/auth_api.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/token-badge.tsx
/// Header token badge displaying live balance, coins icon & "100 tokens = 1 scan".

class TokenBadgeWidget extends StatefulWidget {
  const TokenBadgeWidget({super.key});

  @override
  State<TokenBadgeWidget> createState() => _TokenBadgeWidgetState();
}

class _TokenBadgeWidgetState extends State<TokenBadgeWidget> {
  Timer? _timer;
  bool _unlimited = true;
  int? _balance;
  int _scanCost = 100;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTokens();
    // Poll every 5 seconds as in components/cmt/token-badge.tsx
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchTokens());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(SESSION_COOKIE);
      final res = await AuthApi.getTokens(token);
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _unlimited = res.data['unlimited'] == true;
          _balance = (res.data['balance'] as num?)?.toInt();
          _scanCost = (res.data['scanCost'] as num?)?.toInt() ?? 100;
          _isLoading = false;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _balance == null && !_unlimited) {
      return const SizedBox.shrink();
    }

    final low = !_unlimited && (_balance ?? 0) < _scanCost;
    final borderColor = low ? AppTheme.destructive.withOpacity(0.5) : AppTheme.warning.withOpacity(0.4);
    final bgColor = low ? AppTheme.destructive.withOpacity(0.12) : AppTheme.warning.withOpacity(0.12);
    final textColor = low ? AppTheme.destructive : AppTheme.warning;

    return Tooltip(
      message: '1 scan = $_scanCost tokens',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.monetization_on,
                size: 11,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _unlimited ? '∞' : '$_balance',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'tokens',
              style: TextStyle(
                fontSize: 10,
                color: textColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
