import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/scan_service.dart';

class LogsPanel extends StatefulWidget {
  const LogsPanel({super.key});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanService = context.watch<ScanService>();
    final logs = scanService.liveLogs;

    // Auto-scroll to bottom on new log
    if (_autoScroll && logs.isNotEmpty && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal, color: Color(0xFF38BDF8), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Realtime System & FFmpeg Logs',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _autoScroll ? Icons.vertical_align_bottom : Icons.pause_circle_outline,
                      size: 16,
                      color: _autoScroll ? const Color(0xFF38BDF8) : Colors.white38,
                    ),
                    tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll PAUSED',
                    onPressed: () => setState(() => _autoScroll = !_autoScroll),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy all logs',
                    onPressed: () {
                      final all = logs.join('\n');
                      Clipboard.setData(ClipboardData(text: all));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 160,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(8),
            ),
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No system logs generated yet.',
                      style: TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'monospace'),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      final isError = log.toLowerCase().contains('error') || log.toLowerCase().contains('failed');
                      final isMatch = log.toLowerCase().contains('match');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          log,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: isError
                                ? const Color(0xFFEF4444)
                                : (isMatch ? const Color(0xFF34D399) : Colors.white70),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
