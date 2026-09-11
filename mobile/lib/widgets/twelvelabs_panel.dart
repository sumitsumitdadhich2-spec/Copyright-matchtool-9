import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/formatters.dart';

class TwelveLabsPanel extends StatefulWidget {
  final Scan scan;

  const TwelveLabsPanel({super.key, required this.scan});

  @override
  State<TwelveLabsPanel> createState() => _TwelveLabsPanelState();
}

class _TwelveLabsPanelState extends State<TwelveLabsPanel> {
  bool _isIndexing = false;
  int _currentStep = 0;
  final List<String> _steps = [
    'Compatibility Check',
    'Video Normalize',
    'Upload to Index',
    'Marengo Indexing',
    'Pegasus Semantic Segmentation',
    'Generate Minute Suggestions',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.hub_outlined, color: Color(0xFF818CF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'TwelveLabs & Pegasus Pre-Filter',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF818CF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'MARENGO + PEGASUS',
                  style: TextStyle(fontSize: 9, color: Color(0xFFA5B4FC), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'TwelveLabs Marengo embeddings & Pegasus video summarizer to pre-filter candidate movie minutes.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 12),

          // Pipeline Step Progress
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _steps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final isDone = i < _currentStep;
              final isCurrent = i == _currentStep && _isIndexing;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? const Color(0xFF818CF8).withOpacity(0.1)
                      : (isDone ? Colors.black26 : Colors.white.withOpacity(0.02)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCurrent ? const Color(0xFF818CF8).withOpacity(0.4) : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    if (isCurrent)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF818CF8)),
                      )
                    else if (isDone)
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14)
                    else
                      const Icon(Icons.radio_button_unchecked, color: Colors.white30, size: 14),
                    const SizedBox(width: 8),
                    Text(
                      '${i + 1}. ${_steps[i]}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? const Color(0xFFA5B4FC) : (isDone ? Colors.white : Colors.white60),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isIndexing
                  ? null
                  : () async {
                      setState(() {
                        _isIndexing = true;
                        _currentStep = 0;
                      });

                      for (int step = 0; step < _steps.length; step++) {
                        await Future.delayed(const Duration(milliseconds: 600));
                        if (mounted) setState(() => _currentStep = step + 1);
                      }

                      if (mounted) {
                        setState(() => _isIndexing = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('TwelveLabs & Pegasus segmentation complete!')),
                        );
                      }
                    },
              icon: _isIndexing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 16),
              label: Text(
                _isIndexing ? 'Indexing Video (${_currentStep}/${_steps.length})...' : 'Run TwelveLabs Pipeline',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF818CF8),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
