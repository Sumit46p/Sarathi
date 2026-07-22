import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String _baseUrl = 'http://10.47.169.138:8000';
  static const _storage = FlutterSecureStorage();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static Future<Map<String, String>> _authHeaders() async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      return {
        ..._jsonHeaders,
        'Authorization': 'Bearer $token',
      };
    }
    return _jsonHeaders;
  }

  static Future<void> _setTokens(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  static Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  static Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      _log('login status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access = data['access'] as String?;
        final refresh = data['refresh'] as String?;
        if (access != null && refresh != null) {
          await _setTokens(access, refresh);
          return true;
        }
      }
      return false;
    } catch (e) {
      _log('login exception: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getDriverMe() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/api/drivers/me/'), headers: headers)
          .timeout(const Duration(seconds: 15));

      _log('getDriverMe status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data;
      }
      return null;
    } catch (e) {
      _log('getDriverMe exception: $e');
      return null;
    }
  }

  static Future<bool> updateVehicleAvailability({
    required int vehicleId,
    required bool isAvailable,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/vehicles/$vehicleId/'),
            headers: headers,
            body: jsonEncode({'is_available': isAvailable}),
          )
          .timeout(const Duration(seconds: 15));

      _log('updateVehicleAvailability status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      _log('updateVehicleAvailability exception: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> setDutyStatus({
    required bool isOnDuty,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/drivers/me/duty/'),
            headers: headers,
            body: jsonEncode({'is_on_duty': isOnDuty}),
          )
          .timeout(const Duration(seconds: 15));

      _log('setDutyStatus status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _log('setDutyStatus exception: $e');
      return null;
    }
  }

  static Future<bool> reportIssue({
    required String description,
    File? image,
  }) async {
    try {
      final token = await _storage.read(key: 'access_token');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/drivers/me/report-issue/'),
      );

      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields['description'] = description;

      if (image != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', image.path),
        );
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      _log('reportIssue status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      _log('reportIssue exception: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getMyDispatch() async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .get(Uri.parse('$_baseUrl/api/drivers/me/dispatch/'), headers: headers)
          .timeout(const Duration(seconds: 15));

      _log('getMyDispatch status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _log('getMyDispatch exception: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> transitionDispatch({
    required String status,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/drivers/me/dispatch/transition/'),
            headers: headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 15));

      _log('transitionDispatch status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _log('transitionDispatch exception: $e');
      return null;
    }
  }

  static Future<bool> updateLocation({
    required int vehicleId,
    required double lat,
    required double lng,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/vehicles/$vehicleId/update-location/'),
            headers: headers,
            body: jsonEncode({'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 15));

      _log('updateLocation status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      _log('updateLocation exception: $e');
      return false;
    }
  }

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

  static void _log(String message) => print('[ApiService] $message');
}
