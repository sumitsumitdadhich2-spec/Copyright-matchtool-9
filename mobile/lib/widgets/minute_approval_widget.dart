import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/formatters.dart';

class MinuteApprovalWidget extends StatefulWidget {
  final Scan scan;
  final VoidCallback? onApproved;

  const MinuteApprovalWidget({
    super.key,
    required this.scan,
    this.onApproved,
  });

  @override
  State<MinuteApprovalWidget> createState() => _MinuteApprovalWidgetState();
}

class _MinuteApprovalWidgetState extends State<MinuteApprovalWidget> {
  final Set<int> _selectedMinutes = {};
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final chunkCount = widget.scan.chunkCount;
    if (chunkCount == 0) return const SizedBox.shrink();

    // Default: first 5 or all chunks selected
    if (!_initialized) {
      _selectedMinutes.addAll(List.generate(chunkCount.clamp(1, 10), (i) => i));
      _initialized = true;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.checklist, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Approve Movie Minutes for Scan',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_selectedMinutes.length}/$chunkCount SELECTED',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pegasus / Prescan se suggest hue minutes review karein. Gemini sirf in approved minutes par compare karega.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),

          // Checkboxes list
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: chunkCount,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
              itemBuilder: (context, i) {
                final isChecked = _selectedMinutes.contains(i);
                final startSec = i * 60.0;
                final endSec = (i + 1) * 60.0;

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isChecked) {
                        _selectedMinutes.remove(i);
                      } else {
                        _selectedMinutes.add(i);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                          color: isChecked ? const Color(0xFF38BDF8) : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Minute #${i + 1} (${Formatters.formatDuration(startSec)} - ${Formatters.formatDuration(endSec)})',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isChecked ? Colors.white : Colors.white60,
                            fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('Suggested', style: TextStyle(fontSize: 9, color: Colors.white54)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Select All / Approve Button
          Row(
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    if (_selectedMinutes.length == chunkCount) {
                      _selectedMinutes.clear();
                    } else {
                      _selectedMinutes.addAll(List.generate(chunkCount, (i) => i));
                    }
                  });
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(
                  _selectedMinutes.length == chunkCount ? 'Deselect All' : 'Select All',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _selectedMinutes.isEmpty
                      ? null
                      : () {
                          widget.onApproved?.call();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Approved ${_selectedMinutes.length} minutes for targeted AI scanning.',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.check, size: 16),
                  label: Text('Approve & Lock Scan (${_selectedMinutes.length} Min)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
