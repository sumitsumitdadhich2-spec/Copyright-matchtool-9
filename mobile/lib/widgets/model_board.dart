import 'package:flutter/material.dart';
import '../models/scan.dart';
import '../utils/models.dart';

class ModelBoard extends StatelessWidget {
  final Scan scan;

  const ModelBoard({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    final activeChunkModel = scan.selectedModel ?? AppModels.defaultChunkModel;

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
                  Icon(Icons.memory, color: Color(0xFF818CF8), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Model Pool (Live Web Matching)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '250K TPM CAP · 24 FPS',
                  style: TextStyle(fontSize: 9, color: Color(0xFF34D399), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grid of locked models exactly like web app's ModelBoard
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppModels.allModels.map((m) {
              final isCurrent = m.id == activeChunkModel;
              return Container(
                width: (MediaQuery.of(context).size.width - 60) / 2,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFF818CF8).withOpacity(0.12) : Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent ? const Color(0xFF818CF8) : Colors.white10,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            m.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: isCurrent ? const Color(0xFFA5B4FC) : Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${m.rpd} RPD',
                            style: const TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.role,
                      style: const TextStyle(fontSize: 9, color: Colors.white54),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
