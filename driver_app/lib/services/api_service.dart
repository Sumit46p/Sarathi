import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Exception hierarchy ────────────────────────────────────────────────────
// Every API failure is surfaced as an [ApiException] so call sites can
// distinguish network problems from auth issues from server errors without
// inspecting raw HTTP status codes.

class ApiException implements Exception {
  final String message;
  final ApiErrorKind kind;
  final int? statusCode;

  const ApiException({
    required this.message,
    required this.kind,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException($kind): $message';
}

enum ApiErrorKind {
  /// No internet, DNS failure, timeout, or SocketException.
  network,

  /// HTTP 401 — access token is invalid or expired.
  unauthorized,

  /// HTTP 404 — resource does not exist (e.g. no active dispatch).
  notFound,

  /// HTTP 4xx other than 401/404.
  client,

  /// HTTP 5xx.
  server,

  /// Any non-HTTP exception that doesn't match the above (parse errors, etc.).
  unknown,
}

// ── Login result ──────────────────────────────────────────────────────────
// Instead of a bare [bool], [login] now returns a [LoginResult] so the UI
// can show different messages for network errors vs bad credentials.

enum LoginOutcome { success, invalidCredentials, networkError }

class LoginResult {
  final LoginOutcome outcome;
  final String? detail;

  const LoginResult({required this.outcome, this.detail});
}

// ── Force-logout broadcast ────────────────────────────────────────────────
// When the refresh token is also expired (or missing), the interceptor
// broadcasts on this controller.  The app shell (NavigatorObserver or a
// similar wrapper) listens and redirects to the login screen with a
// "session expired" message.

final forceLogoutController = StreamController<void>.broadcast();

// ── API service ────────────────────────────────────────────────────────────

class ApiService {
  // Using 127.0.0.1 on all platforms because:
  // - On physical Android: adb reverse tcp:8000 tcp:8000 tunnels it to the PC
  // - On emulator: 10.0.2.2 would be needed but adb reverse works too
  // - On desktop/web: 127.0.0.1 is localhost directly
  // Run `adb reverse tcp:8000 tcp:8000` each time you connect the phone.
  static const String _baseUrl = 'http://127.0.0.1:8000';

  static const _storage = FlutterSecureStorage();

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Token helpers ──────────────────────────────────────────────────────

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

  // ── Centralized 401 refresh (single-flight) ────────────────────────────
  // When any authenticated request returns 401, we attempt a single token
  // refresh.  Concurrent 401s share the same in-flight promise so the
  // refresh endpoint is hit at most once per expiry window.  If refresh
  // also fails we broadcast a force-logout and throw.

  static Future<void> _performForceLogout() async {
    await clearTokens();
    forceLogoutController.add(null);
  }

  static Future<Map<String, String>> _refreshHeaders() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) {
      await _performForceLogout();
      throw const ApiException(
        message: 'Session expired. Please log in again.',
        kind: ApiErrorKind.unauthorized,
      );
    }
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login/refresh/'),
            headers: _jsonHeaders,
            body: jsonEncode({'refresh': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access = data['access'] as String?;
        if (access != null) {
          await _storage.write(key: 'access_token', value: access);
          return {
            ..._jsonHeaders,
            'Authorization': 'Bearer $access',
          };
        }
      }
      // Refresh endpoint returned non-200 — session is dead.
      await _performForceLogout();
      throw const ApiException(
        message: 'Session expired. Please log in again.',
        kind: ApiErrorKind.unauthorized,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      await _performForceLogout();
      throw const ApiException(
        message: 'Session expired. Please log in again.',
        kind: ApiErrorKind.unauthorized,
      );
    }
  }

  // Mutex-like: only one refresh in flight at a time.
  static Future<Map<String, String>>? _inFlightRefresh;

  static Future<Map<String, String>> _refreshOrShare() {
    return _inFlightRefresh ??= _refreshHeaders().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  /// Sends an authenticated request.  On 401, silently refreshes the token
  /// and retries once.  All other errors are converted to [ApiException].
  static Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function(Map<String, String> headers) fn,
  ) async {
    var headers = await _authHeaders();
    http.Response response;
    try {
      response = await fn(headers).timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const ApiException(
        message: 'No internet connection. Please check your network and try again.',
        kind: ApiErrorKind.network,
      );
    } on TimeoutException {
      throw const ApiException(
        message: 'Request timed out. The server may be slow or unreachable.',
        kind: ApiErrorKind.network,
      );
    } on http.ClientException {
      throw const ApiException(
        message: 'Network error. Please check your connection.',
        kind: ApiErrorKind.network,
      );
    }

    if (response.statusCode == 401) {
      // Attempt silent refresh + retry.
      try {
        headers = await _refreshOrShare();
        response = await fn(headers).timeout(const Duration(seconds: 15));
      } on ApiException {
        rethrow; // Already an ApiException (likely unauthorized after refresh fail).
      } on SocketException {
        throw const ApiException(
          message: 'No internet connection during token refresh.',
          kind: ApiErrorKind.network,
        );
      } on TimeoutException {
        throw const ApiException(
          message: 'Token refresh timed out.',
          kind: ApiErrorKind.network,
        );
      } on http.ClientException {
        throw const ApiException(
          message: 'Network error during token refresh.',
          kind: ApiErrorKind.network,
        );
      }
    }

    // Convert non-2xx to ApiException for call-site consumption.
    if (response.statusCode >= 400) {
      final body = _safeParseJson(response.body);
      final serverMessage = body?['error']?.toString() ??
          body?['detail']?.toString() ??
          (body is Map
              ? (body as Map).values
                  .whereType<List>()
                  .expand((e) => e)
                  .firstOrNull
                  ?.toString()
              : null);

      final kind = response.statusCode == 401
          ? ApiErrorKind.unauthorized
          : response.statusCode == 404
              ? ApiErrorKind.notFound
              : response.statusCode >= 500
                  ? ApiErrorKind.server
                  : ApiErrorKind.client;

      throw ApiException(
        message: serverMessage ?? _defaultMessage(response.statusCode),
        kind: kind,
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  static String _defaultMessage(int status) {
    if (status == 401) return 'Session expired. Please log in again.';
    if (status == 403) return 'You do not have permission for this action.';
    if (status == 404) return 'Requested resource was not found.';
    if (status >= 500) return 'Server error. Please try again later.';
    return 'Request failed ($status).';
  }

  static Map<String, dynamic>? _safeParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Public API methods ──────────────────────────────────────────────────

  static Future<LoginResult> login({
    required String username,
    required String password,
    required String organizationName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/auth/login/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'username': username,
              'password': password,
              'organization_name': organizationName,
            }),
          )
          .timeout(const Duration(seconds: 15));

      _log('login status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final access = data['access'] as String?;
        final refresh = data['refresh'] as String?;
        if (access != null && refresh != null) {
          await _setTokens(access, refresh);
          return const LoginResult(outcome: LoginOutcome.success);
        }
      }
      
      // Extract error message from server response
      String? serverMessage;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        serverMessage = body['error']?.toString() ??
            body['detail']?.toString() ??
            body['non_field_errors']?.first?.toString();
      } catch (_) {
        // Response is not valid JSON
      }
      
      // Return appropriate error based on status code
      if (response.statusCode == 401 || response.statusCode == 400) {
        return LoginResult(
          outcome: LoginOutcome.invalidCredentials,
          detail: serverMessage ?? 'Invalid username, organization, or password',
        );
      } else if (response.statusCode >= 500) {
        return LoginResult(
          outcome: LoginOutcome.networkError,
          detail: serverMessage ?? 'Server error. Please try again later.',
        );
      }
      
      return LoginResult(
        outcome: LoginOutcome.invalidCredentials,
        detail: serverMessage ?? 'Login failed. Please check your credentials and try again.',
      );
    } on SocketException {
      return const LoginResult(
        outcome: LoginOutcome.networkError,
        detail: 'Cannot reach the server. Please ensure adb reverse is set up: adb reverse tcp:8000 tcp:8000',
      );
    } on TimeoutException {
      return const LoginResult(
        outcome: LoginOutcome.networkError,
        detail: 'Connection timed out. The server may be unreachable or too slow to respond.',
      );
    } on http.ClientException catch (e) {
      return LoginResult(
        outcome: LoginOutcome.networkError,
        detail: 'Network error: ${e.message}. Please check your connection.',
      );
    } catch (e) {
      return LoginResult(
        outcome: LoginOutcome.networkError,
        detail: 'Unexpected error: ${e.toString()}',
      );
    }
  }

  static Future<Map<String, dynamic>?> getDriverMe() async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.get(Uri.parse('$_baseUrl/api/drivers/me/'), headers: headers),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException catch (e) {
      _log('getDriverMe failed: $e');
      rethrow;
    }
  }

  static Future<bool> changePassword(String newPassword) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.post(
          Uri.parse('$_baseUrl/api/drivers/me/change-password/'),
          headers: headers,
          body: jsonEncode({'new_password': newPassword}),
        ),
      );
      return response.statusCode == 200;
    } on ApiException {
      return false;
    }
  }

  static Future<bool> resetPassword({
    required String username,
    required String organizationName,
    required String newPassword,
  }) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.post(
          Uri.parse('$_baseUrl/api/drivers/reset-password/'),
          headers: headers,
          body: jsonEncode({
            'username': username,
            'organization_name': organizationName,
            'new_password': newPassword,
          }),
        ),
      );
      return response.statusCode == 200;
    } on ApiException {
      return false;
    }
  }

  static Future<bool> verifyForgotPasswordIdentity({
    required String username,
    required String organizationName,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/drivers/verify-identity/'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'username': username,
              'organization_name': organizationName,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      _log('verifyForgotPasswordIdentity exception: $e');
      return false;
    }
  }

  static Future<bool> updateVehicleAvailability({
    required int vehicleId,
    required bool isAvailable,
  }) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.patch(
          Uri.parse('$_baseUrl/api/vehicles/$vehicleId/'),
          headers: headers,
          body: jsonEncode({'is_available': isAvailable}),
        ),
      );
      _log('updateVehicleAvailability status: ${response.statusCode}');
      return response.statusCode == 200;
    } on ApiException {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> setDutyStatus({
    required bool isOnDuty,
  }) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.patch(
          Uri.parse('$_baseUrl/api/drivers/me/duty/'),
          headers: headers,
          body: jsonEncode({'is_on_duty': isOnDuty}),
        ),
      );
      _log('setDutyStatus status: ${response.statusCode}');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException catch (e) {
      _log('setDutyStatus exception: $e');
      rethrow;
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

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      _log('reportIssue status: ${response.statusCode}');
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      _log('reportIssue exception: $e');
      return false;
    }
  }

  /// Returns the driver's active dispatch, or [null] if there is none (404).
  /// Throws [ApiException] on network/server/auth errors.
  static Future<Map<String, dynamic>?> getMyDispatch() async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.get(
          Uri.parse('$_baseUrl/api/drivers/me/dispatch/'),
          headers: headers,
        ),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.notFound) {
        // 404 means no active dispatch — not an error.
        return null;
      }
      _log('getMyDispatch failed: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> transitionDispatch({
    required String status,
  }) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.post(
          Uri.parse('$_baseUrl/api/drivers/me/dispatch/transition/'),
          headers: headers,
          body: jsonEncode({'status': status}),
        ),
      );
      _log('transitionDispatch status: ${response.statusCode}');
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on ApiException catch (e) {
      _log('transitionDispatch exception: $e');
      rethrow;
    }
  }

  static Future<bool> updateLocation({
    required int vehicleId,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _authenticatedRequest(
        (headers) => http.post(
          Uri.parse('$_baseUrl/api/vehicles/$vehicleId/update-location/'),
          headers: headers,
          body: jsonEncode({'lat': lat, 'lng': lng}),
        ),
      );
      return response.statusCode == 200;
    } on ApiException catch (e) {
      _log('updateLocation exception: $e');
      rethrow;
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

      final streamed =
          await request.send().timeout(const Duration(seconds: 30));
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
