import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'api_key_manager_widget.dart';
import 'engine_badge_widget.dart';

/// 1:1 Port of components/cmt/settings-dialog.tsx
/// Settings dialog with API Key configuration, Engine Badge, and escape/backdrop dismiss.

class SettingsDialog extends StatelessWidget {
  final VoidCallback onClose;

  const SettingsDialog({super.key, required this.onClose});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SettingsDialog(onClose: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
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
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_outlined, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Settings — API Keys',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                const EngineBadgeWidget(),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),

          // Body
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ApiKeyManagerWidget(),
            ),
          ),
        ],
      ),
    );
  }
}
