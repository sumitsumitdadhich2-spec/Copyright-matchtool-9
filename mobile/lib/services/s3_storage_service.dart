import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 1:1 Port of lib/storage.ts
/// Durable storage integration with Amazon S3 / S3-compatible endpoints for remote synchronization.

class ListedObject {
  final String key;
  final int size;
  final int lastModified;

  ListedObject({
    required this.key,
    required this.size,
    required this.lastModified,
  });
}

class S3StorageService {
  static final String s3Bucket = Platform.environment['S3_BUCKET'] ?? '';
  static final String awsRegion = Platform.environment['AWS_REGION'] ?? Platform.environment['AWS_DEFAULT_REGION'] ?? 'ap-south-1';
  static final String? s3Endpoint = Platform.environment['S3_ENDPOINT'];

  /// True when S3 bucket is configured
  static bool storageEnabled() => s3Bucket.isNotEmpty;

  /// Put small string / JSON
  static Future<void> putObject(String key, String body, {String contentType = 'application/octet-stream'}) async {
    if (!storageEnabled()) return;
    // S3 HTTP REST PUT request
    final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
    final uri = Uri.parse('$endpoint/$key');
    await http.put(
      uri,
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'no-store',
      },
      body: body,
    );
  }

  static Future<void> putObjectJSON(String key, dynamic data) async {
    await putObject(key, jsonEncode(data), contentType: 'application/json');
  }

  /// Get object text
  static Future<String?> getObjectText(String key) async {
    if (!storageEnabled()) return null;
    try {
      final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
      final uri = Uri.parse('$endpoint/$key');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        return resp.body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get object parsed JSON
  static Future<T?> getObjectJSON<T>(String key) async {
    final text = await getObjectText(key);
    if (text == null) return null;
    try {
      return jsonDecode(text) as T;
    } catch (_) {
      return null;
    }
  }

  /// Delete object
  static Future<void> deleteObject(String key) async {
    if (!storageEnabled()) return;
    try {
      final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
      final uri = Uri.parse('$endpoint/$key');
      await http.delete(uri);
    } catch (_) {}
  }

  /// Upload local file
  static Future<void> putFile(String key, String localPath, {String contentType = 'application/octet-stream'}) async {
    if (!storageEnabled()) return;
    final file = File(localPath);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
    final uri = Uri.parse('$endpoint/$key');
    await http.put(uri, headers: {'Content-Type': contentType}, body: bytes);
  }

  /// Download object to local file
  static Future<bool> getFile(String key, String localPath) async {
    if (!storageEnabled()) return false;
    try {
      final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
      final uri = Uri.parse('$endpoint/$key');
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return false;
      final file = File(localPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(resp.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Object existence check
  static Future<bool> objectExists(String key) async {
    if (!storageEnabled()) return false;
    try {
      final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
      final uri = Uri.parse('$endpoint/$key');
      final resp = await http.head(uri);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Storage health check
  static Future<Map<String, dynamic>> storageHealthy() async {
    if (!storageEnabled()) return {'ok': false, 'error': 'S3_BUCKET not set'};
    try {
      final endpoint = s3Endpoint ?? 'https://$s3Bucket.s3.$awsRegion.amazonaws.com';
      final uri = Uri.parse('$endpoint/?max-keys=1');
      final resp = await http.get(uri);
      return {'ok': resp.statusCode == 200};
    } catch (err) {
      return {'ok': false, 'error': err.toString()};
    }
  }
}
