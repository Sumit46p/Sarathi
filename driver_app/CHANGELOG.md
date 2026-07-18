# Changelog

### [v1.0.5] - Advanced Features & Backend Integration
- **Added**: `ProfileScreen` — fetches driver data from Firestore, supports profile photo upload to Firebase Storage.
- **Added**: `TripsScreen` — live Firestore stream showing allocated trips for the logged-in driver.
- **Added**: `SOSScreen` — gets GPS location via `geolocator`, writes emergency to Firestore, shows Leaflet map (`flutter_map`) with nearby drivers.
- **Added**: `CameraLogScreen` — opens native camera, uploads image to Firebase Storage, creates log in Firestore for admin review (shared by Fuel Entry & Maintenance).
- **Changed**: `DashboardScreen` — all quick actions now navigate to real screens; overview stats are live from Firestore.
- **Changed**: `signup_screen.dart` — saves full driver profile to `drivers` Firestore collection on registration.
- **Changed**: `main.dart` — Auth state routing: logged-in users skip Splash and go directly to Dashboard.
- **Added**: Android permissions for Camera, Location, Storage in `AndroidManifest.xml`.
- **Changed**: `minSdk` bumped to 21 for package compatibility.

### [v1.0.4] - Dashboard UI Overhaul
- **Added**: Detailed `DashboardScreen` layout with Bottom Navigation Bar.
- **Added**: Status toggle dropdown in the top bar with dynamic color coding.
- **Added**: Reusable `StatCard` widget for displaying "Today's Overview" metrics (Trips, Distance, Time, Efficiency).
- **Added**: Reusable `ActionButton` widget for "Quick Actions" grid (Start Duty, SOS, Fuel, Report Issue, Maintenance, Messages).

### [v1.0.3] - New Firebase Project
- **Changed**: `google-services.json` replaced with new Firebase project (`sarathi-3a7e9`).
- **Changed**: `applicationId` and `namespace` updated to `com.company.sarthi`.
- **Changed**: `MainActivity.kt` moved to `kotlin/com/company/sarthi/` with updated package declaration.

### [v1.0.2] - Branding & Forgot Password
- **Added**: `ForgotPasswordScreen` with Firebase `sendPasswordResetEmail` integration.
- **Added**: Animated success state on `ForgotPasswordScreen` after email is sent.
- **Changed**: App name set to `Sarathi` in `AndroidManifest.xml`.
- **Changed**: App launcher icon replaced with `assets/images/logo.png` using `flutter_launcher_icons`.
- **Changed**: `Forgot Password?` button in `login_screen.dart` now navigates to `ForgotPasswordScreen`.

### [v1.0.1] - Firebase Authentication Integration
- **Fixed**: `applicationId` mismatch error during Android build.
- **Added**: `firebase_core` and `firebase_auth` dependencies.
- **Added**: `google-services.json` setup for Android.
- **Added**: Firebase initialization in `lib/main.dart`.
- **Changed**: `login_screen.dart` uses `FirebaseAuth.instance.signInWithEmailAndPassword`.
- **Changed**: `signup_screen.dart` uses `FirebaseAuth.instance.createUserWithEmailAndPassword`.

### [v1.0.0] - Initial UI & Architecture Setup
- **Added**: Project structure (`screens/`, `widgets/`).
- **Added**: Material 3 `theme.dart`.
- **Added**: Authentication screens UI (Login/Signup).
- **Added**: Dashboard UI.
