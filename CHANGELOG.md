# Changelog

## [Unreleased]

### Added
- **Flutter Driver App**
  - Added new mandatory password change dialog on first login for drivers (driven by `requires_password_change` flag).
  - Added "Forgot Password" flow allowing drivers to reset passwords using their license number.
  - Implemented dynamic API URL resolution handling `localhost` on web/desktop and `adb reverse` loopback correctly.
  - Wired up Quick Actions in the Dashboard (Fuel Entry, Report Issue, Inspect Vehicle) to prompt for camera permissions and launch the camera to log notes.
  - Wired up the SOS Quick Action to launch the emergency dialer (100).
- **Admin Dashboard (React)**
  - Added the official Sarathi logo to the Admin Dashboard sidebar header.

### Fixed
- **Backend / Admin**
  - Fixed vehicle creation crash in the Django admin API (removed stale NOT NULL `license_plate` requirement at the database level).
  - Fixed bug where deleting a driver didn't cascade delete their login `User` record, preventing the reuse of usernames for new drivers.
  - Added missing `Profile` objects for existing admin users which previously caused a 500 error when they tried to view their profile or create objects.
  - Made `UserSerializer` resilient against missing `Profile` objects to prevent 500 API crashes.
- **Flutter Driver App**
  - Fixed login `TimeoutException` by instructing use of `0.0.0.0:8000` binding or `adb reverse tcp:8000 tcp:8000`.
