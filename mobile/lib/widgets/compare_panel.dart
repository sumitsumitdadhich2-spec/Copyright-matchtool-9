import 'package:flutter/material.dart';
import '../models/scan.dart';
import 'compare_studio_panel.dart';

/// 1:1 Export / Alias of components/cmt/compare-panel.tsx
class ComparePanel extends StatelessWidget {
  final Scan scan;

  const ComparePanel({super.key, required this.scan});

  @override
  Widget build(BuildContext context) {
    return CompareStudioPanel(scan: scan);
  }
}
