# Flutter API Endpoint Fix

## Issue
The Flutter driver app was repeatedly showing this error:
```
[ApiService] getDriverMe failed: ApiException(ApiErrorKind.network): No internet connection. 
Please check your network and try again.
```

This error appeared even though:
- The backend server was running on `http://127.0.0.1:8000`
- Device setup (adb reverse) was configured
- The robustness audit had passed

## Root Cause
**Incorrect endpoint URL in Flutter ApiService**

The Flutter app's `getDriverMe()` method was calling:
```
/api/drivers/me/
```

But the correct endpoint (as defined in Django backend) is:
```
/api/auth/me/
```

### Why This Happened
- The backend routes `/api/auth/*` through the `accounts` app (Django auth module)
- The user detail endpoint is at `/api/auth/me/` in `accounts/urls.py`
- The Flutter app incorrectly assumed a `/api/drivers/me/` endpoint that doesn't exist
- This caused 404 errors to be wrapped as network errors by the ApiService exception handler

### Backend Evidence
**sarthi_backend/urls.py:**
```python
urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/auth/', include('accounts.urls')),  # ← Auth endpoints here
    path('api/', include('vehicles.urls')),
]
```

**accounts/urls.py:**
```python
urlpatterns = [
    path('login/', LoginView.as_view(), name='token_obtain_pair'),
    path('login/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('register/', RegisterView.as_view(), name='register'),
    path('me/', UserDetailView.as_view(), name='user_detail'),  # ← Here at /api/auth/me/
    path('verify-admin/', VerifyAdminUserView.as_view(), name='verify_admin'),
    path('reset-admin-password/', ResetAdminPasswordView.as_view(), name='reset_admin_password'),
]
```

## Fix Applied
**File:** `driver_app/lib/services/api_service.dart`  
**Method:** `getDriverMe()` (line 371)

**Before:**
```dart
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
```

**After:**
```dart
static Future<Map<String, dynamic>?> getDriverMe() async {
  try {
    final response = await _authenticatedRequest(
      (headers) => http.get(Uri.parse('$_baseUrl/api/auth/me/'), headers: headers),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  } on ApiException catch (e) {
    _log('getDriverMe failed: $e');
    rethrow;
  }
}
```

## Result
✅ The Flutter app will now correctly fetch the user's profile data from `/api/auth/me/`  
✅ Network errors will be genuine network issues, not 404 wrapping  
✅ Profile screen will load user data on app launch  

## Next Steps
1. Rebuild the Flutter app with the updated ApiService
2. Run the app and verify the profile loads without repeated errors
3. Monitor logs to confirm `/api/auth/me/` is being called instead of `/api/drivers/me/`

---

**Note**: This was not a robustness issue (the previous audit was correct about error handling). This was a configuration/routing mismatch between the Flutter client and Django backend API structure.