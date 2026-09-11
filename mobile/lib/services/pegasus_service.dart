import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/scan.dart';

/// 1:1 Port of lib/pegasus.ts
/// TwelveLabs Asset & Pegasus 1.5 Segmentation Service.

class SegmentDefinitionField {
  final String name;
  final String type;
  final String description;

  const SegmentDefinitionField({
    required this.name,
    required this.type,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
      };
}

class SegmentDefinition {
  final String id;
  final String description;
  final List<SegmentDefinitionField> fields;

  const SegmentDefinition({
    required this.id,
    required this.description,
    required this.fields,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'fields': fields.map((f) => f.toJson()).toList(),
      };
}

class PegasusService {
  static const String tlBase = 'https://api.twelvelabs.io/v1.3';
  static const String pegasusModel = 'pegasus1.5';
  static const int pegasusMaxTokens = 96000;
  static const double pegasusMaxDurationSec = 2 * 60 * 60.0;

  static String _hms(double totalSec) {
    final s = [0, totalSec.round()].reduce((a, b) => a > b ? a : b);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  /// Exact 4 segment definitions from TwelveLabs playground
  static List<SegmentDefinition> buildSegmentDefinitions(double shortEndSec, double mergedEndSec) {
    final shortEnd = _hms(shortEndSec);
    return [
      SegmentDefinition(
        id: 'segment_1',
        description:
            'Detect every shot cut in PART A only (00:00 to $shortEnd). Find real editorial cuts where image changes to new shot. Output each shot with start/end time.',
        fields: const [
          SegmentDefinitionField(name: 'type_angle_type', type: 'string', description: 'Camera angle: wide, medium, close_up, overhead, aerial'),
          SegmentDefinitionField(name: 'type_description', type: 'string', description: 'Who is in frame, action, background'),
          SegmentDefinitionField(name: 'type_part', type: 'string', description: 'PART A or PART B'),
        ],
      ),
      SegmentDefinition(
        id: 'segment_2',
        description:
            'Track every person visible in PART A (00:00 to $shortEnd). For each new person appearing on screen create a new segment.',
        fields: const [
          SegmentDefinitionField(name: 'person', type: 'string', description: 'Physical description of person - clothing, hair, distinguishing features'),
          SegmentDefinitionField(name: 'activity', type: 'string', description: 'What the person is doing in this segment'),
          SegmentDefinitionField(name: 'speaking', type: 'boolean', description: 'Is this person speaking dialogue'),
        ],
      ),
      SegmentDefinition(
        id: 'segment_3',
        description:
            'Detect all burned-in text overlays visible in PART A (00:00 to $shortEnd). These are text captions added on top of movie frames by the uploader. Ignore original movie subtitles.',
        fields: const [
          SegmentDefinitionField(name: 'overlay_text', type: 'string', description: 'Exact text visible on screen'),
          SegmentDefinitionField(name: 'purpose', type: 'string', description: 'Purpose of text'),
        ],
      ),
      SegmentDefinition(
        id: 'segment_4',
        description:
            'Find exact scenes from PART A that match in PART B. Output corresponding movie timestamp ranges and confidence.',
        fields: const [
          SegmentDefinitionField(name: 'part_a_start', type: 'string', description: 'Start time in PART A'),
          SegmentDefinitionField(name: 'part_a_end', type: 'string', description: 'End time in PART A'),
          SegmentDefinitionField(name: 'part_b_start', type: 'string', description: 'Matched start time in PART B'),
          SegmentDefinitionField(name: 'part_b_end', type: 'string', description: 'Matched end time in PART B'),
          SegmentDefinitionField(name: 'confidence', type: 'string', description: 'Match confidence: high, medium, low'),
        ],
      ),
    ];
  }

  /// Create Asset on TwelveLabs
  static Future<String> createAsset(String apiKey, String filePath) async {
    final uri = Uri.parse('$tlBase/assets');
    final request = http.MultipartRequest('POST', uri);
    request.headers['x-api-key'] = apiKey;
    request.fields['method'] = 'direct';
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: p.basename(filePath)));

    final streamedResp = await request.send();
    final resp = await http.Response.fromStream(streamedResp);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('TwelveLabs asset upload failed (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    final id = data['_id'] ?? data['id'] ?? (data['data'] != null ? data['data']['_id'] : null);
    if (id == null) throw Exception('Asset create returned no id');
    return id.toString();
  }
}
