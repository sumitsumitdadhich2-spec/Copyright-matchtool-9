import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/scan_timing.dart';

class ScanTimingReportWidget extends StatelessWidget {
  final Scan scan;

  const ScanTimingReportWidget({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final timing = ScanTimingSummary.compute(scan);
    if (!timing.hasCompletedTasks) return const SizedBox.shrink();

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
                  Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Task Timing & Execution Duration',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF38BDF8).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Grand Total: ${timing.totalFormatted}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Har kaam ka alag time aur total execution time (Same as Web App)',
            style: TextStyle(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 10),

          // Grid / List of tasks
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: timing.tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final task = timing.tasks[index];
              final isRunning = task.status == 'running';
              final isCompleted = task.status == 'completed';

              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRunning
                      ? const Color(0xFF38BDF8).withOpacity(0.1)
                      : (isCompleted ? Colors.black26 : Colors.white.withOpacity(0.02)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isRunning ? const Color(0xFF38BDF8).withOpacity(0.4) : Colors.white10,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (isRunning)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                          )
                        else if (isCompleted)
                          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16)
                        else
                          const Icon(Icons.radio_button_unchecked, color: Colors.white30, size: 16),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(task.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            Text(task.description, style: const TextStyle(fontSize: 9, color: Colors.white54)),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.durationFormatted,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

typedef ScanTimingReport = ScanTimingReportWidget;
