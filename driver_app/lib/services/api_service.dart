import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Central service that talks to the Sarathi Django + PostgreSQL backend.
/// Base URL points to the local Django dev server (same machine as the emulator).
/// For a physical device on the same WiFi, replace with your PC's LAN IP.
class ApiService {
  // ── Configuration ──────────────────────────────────────────────────────────
  // Android emulator loopback → host PC's localhost
  static const String _baseUrl = 'http://10.0.2.2:8000';

  // Shared JSON headers
  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Driver Registration ────────────────────────────────────────────────────
  /// Called immediately after Firebase Auth creates a new user account.
  /// Persists full driver profile to PostgreSQL via Django.
  ///
  /// Returns `true` on success, `false` on any failure (non-blocking).
  static Future<bool> registerDriver({
    required String firebaseUid,
    required String name,
    required String email,
    required String phone,
    required String vehicleNumber,
    required String department,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/drivers/register/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'firebase_uid': firebaseUid,
              'name': name,
              'email': email,
              'phone': phone,
              'vehicle_number': vehicleNumber,
              'department': department,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        _log('registerDriver failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      _log('registerDriver exception: $e');
      return false;
    }
  }

  // ── Login Event ────────────────────────────────────────────────────────────
  /// Records a login event in PostgreSQL when the driver signs in.
  static Future<bool> recordLogin({
    required String firebaseUid,
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/drivers/login-event/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'firebase_uid': firebaseUid,
              'email': email,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        _log('recordLogin failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      _log('recordLogin exception: $e');
      return false;
    }
  }

  // ── Document Upload Metadata ───────────────────────────────────────────────
  /// After a document is uploaded to Firebase Storage, call this to record
  /// its metadata (URL, type) in PostgreSQL so the admin dashboard can see it.
  static Future<bool> recordDocument({
    required String firebaseUid,
    required String docType,
    required String fileUrl,
    String? fileName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/drivers/documents/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'firebase_uid': firebaseUid,
              'doc_type': docType,
              'file_url': fileUrl,
              'file_name': fileName ?? docType,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        _log('recordDocument failed [${response.statusCode}]: ${response.body}');
        return false;
      }
    } catch (e) {
      _log('recordDocument exception: $e');
      return false;
    }
  }

  // ── Multipart document file upload ────────────────────────────────────────
  /// Uploads the actual license file bytes to Django, which stores it and
  /// saves the path in PostgreSQL. Use this as an alternative to Firebase Storage.
  static Future<String?> uploadDocumentFile({
    required String firebaseUid,
    required File file,
    required String docType,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/drivers/documents/upload/'),
      );
      request.fields['firebase_uid'] = firebaseUid;
      request.fields['doc_type'] = docType;
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['file_url'] as String?;
      } else {
        _log('uploadDocumentFile failed [${response.statusCode}]: ${response.body}');
        return null;
      }
    } catch (e) {
      _log('uploadDocumentFile exception: $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  // ignore: avoid_print
  static void _log(String message) => print('[ApiService] $message');
}
