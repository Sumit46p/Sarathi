# Changelog

## [Unreleased]

### Added
- **Flutter Driver App**
  - Added new mandatory password change dialog on first login for drivers (driven by `requires_password_change` flag).
  - Added "Forgot Password" flow allowing drivers to reset passwords using their license number.
  - Implemented dynamic API URL resolution handling `localhost` on web/desktop and `adb reverse` loopback correctly.
  - Wired up Quick Actions in the Dashboard (Fuel Entry, Report Issue, Inspect Vehicle) to prompt for camera permissions and launch the camera to log notes.
  - Wired up the SOS Quick Action to launch the emergency dialer (100).
  - Reworked the Active Trip screen into a live fleet-tracking view: pulsing unit marker on the map, destination pin, route polyline, trip lifecycle stepper (Assigned → Completed), live progress bar with ETA/remaining/distance stat cells, recenter + zoom map controls, and a scene/unit legend.
  - Added a GPS tracking status card on the driver home dashboard that shows live location-sharing state and last GPS update.
- **Admin Dashboard (React)**
  - Added the official Sarathi logo to the Admin Dashboard sidebar header.
  - Dispatch live-tracking card now shows a trip status stepper, a ticking ETA countdown, the assigned unit name + driver, and highlights the active unit in the fleet rail and on the map with a pulsing ring marker.

### Fixed
- **Backend / Admin**
  - Fixed vehicle creation crash in the Django admin API (removed stale NOT NULL `license_plate` requirement at the database level).
  - Fixed bug where deleting a driver didn't cascade delete their login `User` record, preventing the reuse of usernames for new drivers.
  - Added missing `Profile` objects for existing admin users which previously caused a 500 error when they tried to view their profile or create objects.
  - Made `UserSerializer` resilient against missing `Profile` objects to prevent 500 API crashes.
  - Driver dispatch endpoints (`/api/drivers/me/dispatch/` and its transition) now return the same live tracking payload as the dispatcher view: assigned unit name, driver name, current GPS location, route geometry, remaining distance, ETA, and progress percentage.
- **Flutter Driver App**
  - Fixed login `TimeoutException` by instructing use of `0.0.0.0:8000` binding or `adb reverse tcp:8000 tcp:8000`.
