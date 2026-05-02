import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AWS S3 service with SigV4 signing — mirrors the web app's s3Storage.js
/// Keys are stored identically: bucket=s3-mm-lab, region=eu-west-3
class S3Service {
  // ── Credentials (same as the web app) ──
  static const _accessKey = 'AKIA4MKDW2PVJA4APEX7';
  static const _secretKey = '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';
  static const _region = 'eu-west-3';
  static const _bucket = 's3-mm-lab';

  // ── Singleton ──
  static final S3Service _instance = S3Service._internal();
  factory S3Service() => _instance;
  S3Service._internal();

  // ─────────────────────────────────────────
  // SigV4 helpers
  // ─────────────────────────────────────────

  String _dateStamp(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}';
  }

  String _amzDate(DateTime dt) {
    final u = dt.toUtc();
    return '${_dateStamp(u)}T'
        '${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}Z';
  }

  List<int> _hmac(List<int> key, String msg) =>
      Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

  List<int> _signingKey(String dateStr) {
    final kDate = _hmac(utf8.encode('AWS4$_secretKey'), dateStr);
    final kRegion = _hmac(kDate, _region);
    final kService = _hmac(kRegion, 's3');
    return _hmac(kService, 'aws4_request');
  }

  String _hexSha256(List<int> data) => sha256.convert(data).toString();

  Map<String, String> _signRequest({
    required String method,
    required String objectKey,
    required DateTime now,
    required String payloadHash,
    String contentType = '',
  }) {
    final dateStr = _dateStamp(now);
    final amzDate = _amzDate(now);
    final host = '$_bucket.s3.$_region.amazonaws.com';

    // Canonical headers — must be sorted
    final canonicalHeaders = contentType.isNotEmpty
        ? 'content-type:$contentType\nhost:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n'
        : 'host:$host\nx-amz-content-sha256:$payloadHash\nx-amz-date:$amzDate\n';
    final signedHeaders = contentType.isNotEmpty
        ? 'content-type;host;x-amz-content-sha256;x-amz-date'
        : 'host;x-amz-content-sha256;x-amz-date';

    // URI-encode the object key
    final encodedKey = Uri.encodeFull(objectKey);

    final canonicalReq =
        '$method\n/$encodedKey\n\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    final credScope = '$dateStr/$_region/s3/aws4_request';
    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$credScope\n${_hexSha256(utf8.encode(canonicalReq))}';

    final sigBytes = _signingKey(dateStr);
    final signature = hex.encode(
      Hmac(sha256, sigBytes).convert(utf8.encode(stringToSign)).bytes,
    );

    final auth =
        'AWS4-HMAC-SHA256 Credential=$_accessKey/$credScope, SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      'Authorization': auth,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      if (contentType.isNotEmpty) 'content-type': contentType,
    };
  }

  // ─────────────────────────────────────────
  // Low-level GET / PUT
  // ─────────────────────────────────────────

  Future<String?> _getObject(String objectKey) async {
    final now = DateTime.now().toUtc();
    final emptyHash = _hexSha256([]);
    final host = '$_bucket.s3.$_region.amazonaws.com';
    final uri = Uri.https(host, '/${Uri.encodeFull(objectKey)}');
    final headers = _signRequest(
      method: 'GET',
      objectKey: objectKey,
      now: now,
      payloadHash: emptyHash,
    );
    final response = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 20),
      onTimeout: () => http.Response('timeout', 408),
    );
    if (response.statusCode == 200) return response.body;
    if (response.statusCode == 404) return null;
    throw Exception('S3 GET failed: ${response.statusCode}');
  }

  Future<void> _putObject(
    String objectKey,
    List<int> bodyBytes, {
    String contentType = 'application/json',
  }) async {
    final now = DateTime.now().toUtc();
    final payloadHash = _hexSha256(bodyBytes);
    final host = '$_bucket.s3.$_region.amazonaws.com';
    final uri = Uri.https(host, '/${Uri.encodeFull(objectKey)}');
    final headers = _signRequest(
      method: 'PUT',
      objectKey: objectKey,
      now: now,
      payloadHash: payloadHash,
      contentType: contentType,
    );
    final response = await http.put(
      uri,
      headers: headers,
      body: Uint8List.fromList(bodyBytes),
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('S3 PUT failed: ${response.statusCode} ${response.body}');
    }
  }

  // ─────────────────────────────────────────
  // Public API  (mirrors s3Storage.js)
  // ─────────────────────────────────────────

  /// Load a JSON value (List or Map) from S3; falls back to SharedPreferences cache.
  Future<dynamic> loadJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final body = await _getObject('$key.json');
      if (body == null) return null;
      final data = jsonDecode(body);
      await prefs.setString(key, body);
      return data;
    } catch (e) {
      // Network/S3 error → use local cache
      final cached = prefs.getString(key);
      if (cached != null) return jsonDecode(cached);
      return null;
    }
  }

  /// Load a JSON array; returns [] when absent.
  Future<List<dynamic>> loadData(String key) async {
    final data = await loadJson(key);
    if (data is List) return data;
    return [];
  }

  /// Save data to SharedPreferences immediately, then push to S3 in background.
  Future<void> saveData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(data);
    await prefs.setString(key, jsonStr);
    _putObject('$key.json', utf8.encode(jsonStr)).catchError((e) {
      // S3 write failures are non-fatal (offline support)
    });
  }

  /// Upload a raw file (PDF/image) to S3 and return its S3 key.
  Future<void> uploadFile(String objectKey, List<int> bytes, String mimeType) async {
    await _putObject(objectKey, bytes, contentType: mimeType);
  }

  /// Return a presigned-style download URL for a file stored in S3.
  /// Uses a simple query-string signature (valid 1 h).
  String getPresignedUrl(String objectKey) {
    final now = DateTime.now().toUtc();
    final expires = 3600;
    final dateStr = _dateStamp(now);
    final amzDate = _amzDate(now);
    final host = '$_bucket.s3.$_region.amazonaws.com';
    final credScope = '$dateStr/$_region/s3/aws4_request';
    final cred = Uri.encodeComponent('$_accessKey/$credScope');

    final canonicalQS =
        'X-Amz-Algorithm=AWS4-HMAC-SHA256'
        '&X-Amz-Credential=$cred'
        '&X-Amz-Date=$amzDate'
        '&X-Amz-Expires=$expires'
        '&X-Amz-SignedHeaders=host';
    final encodedKey = Uri.encodeFull(objectKey);
    final canonicalReq =
        'GET\n/$encodedKey\n$canonicalQS\nhost:$host\n\nhost\nUNSIGNED-PAYLOAD';
    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$credScope\n${_hexSha256(utf8.encode(canonicalReq))}';
    final sigBytes = _signingKey(dateStr);
    final signature = hex.encode(
      Hmac(sha256, sigBytes).convert(utf8.encode(stringToSign)).bytes,
    );

    return 'https://$host/$encodedKey?$canonicalQS&X-Amz-Signature=$signature';
  }
}
