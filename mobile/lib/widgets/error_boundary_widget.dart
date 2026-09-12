import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 1:1 Port of components/cmt/error-boundary.tsx
/// Error boundary widget with fallback title, message & retry button.

class ErrorBoundaryWidget extends StatefulWidget {
  final Widget child;
  final String? fallbackTitle;
  final String? fallbackMessage;
  final VoidCallback? onReset;

  const ErrorBoundaryWidget({
    super.key,
    required this.child,
    this.fallbackTitle,
    this.fallbackMessage,
    this.onReset,
  });

  @override
  State<ErrorBoundaryWidget> createState() => _ErrorBoundaryWidgetState();
}

class _ErrorBoundaryWidgetState extends State<ErrorBoundaryWidget> {
  Object? _error;
  bool _hasError = false;

  void reset() {
    setState(() {
      _hasError = false;
      _error = null;
    });
    widget.onReset?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.destructive.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.destructive.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.destructive, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fallbackTitle ?? 'Component render error',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.destructive,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _error?.toString() ?? widget.fallbackMessage ?? 'An unexpected error occurred in this view.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: reset,
                    icon: const Icon(Icons.refresh, size: 14, color: AppTheme.destructive),
                    label: const Text('Retry', style: TextStyle(fontSize: 12, color: AppTheme.destructive, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.destructive.withOpacity(0.4)),
                      backgroundColor: AppTheme.destructive.withOpacity(0.12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return widget.child;
  }
}
