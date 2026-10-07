"""
accounts/permissions.py — Sarathi Role-Based Access Control

Custom DRF permission classes that enforce the RBAC matrix.

  Role              Internal value(s)
  ──────────────────────────────────────
  Admin           → SUPER_ADMIN, ORGANIZATION_ADMIN
  Dispatcher      → FLEET_MANAGER
  Driver          → DRIVER
  Viewer / other  → VIEWER, AUDITOR, OFFICER

All permission classes assume the user is already authenticated
(pair them with IsAuthenticated in permission_classes).
They are intentionally silent on the 403 message so we don't
leak role information to external callers.
"""

from rest_framework import permissions


def _role(request):
    """Return the role string from the user's profile, or None if missing."""
    try:
        return request.user.profile.role
    except AttributeError:
        return None


# ────────────────────────────────────────────────────────────────────────────
# Role sets
# ────────────────────────────────────────────────────────────────────────────

ADMIN_ROLES = frozenset(['SUPER_ADMIN', 'ORGANIZATION_ADMIN'])
DISPATCHER_ROLES = frozenset(['SUPER_ADMIN', 'ORGANIZATION_ADMIN', 'FLEET_MANAGER'])
DRIVER_ROLE = 'DRIVER'
# Any authenticated user with a profile counts as Viewer or higher
ALL_ROLES = frozenset([
    'SUPER_ADMIN', 'ORGANIZATION_ADMIN', 'FLEET_MANAGER',
    'OFFICER', 'DRIVER', 'AUDITOR', 'VIEWER',
])


# ────────────────────────────────────────────────────────────────────────────
# Permission classes
# ────────────────────────────────────────────────────────────────────────────

class IsAdminRole(permissions.BasePermission):
    """
    Grants full write/read access to SUPER_ADMIN and ORGANIZATION_ADMIN.

    Matrix column: ADMIN → Manage
    Used on: fleet CRUD, driver CRUD, maintenance CRUD, dispatch override,
             rules/alerts management, analytics.
    """
    message = 'This action requires an Admin role.'

    def has_permission(self, request, view):
        return _role(request) in ADMIN_ROLES


class IsDispatcherOrAdmin(permissions.BasePermission):
    """
    Grants access to FLEET_MANAGER (Dispatcher) plus both Admin tiers.

    Matrix column: DISPATCH → Manage (Dispatcher), ADMIN → Manage (Admin)
    Used on: creating/cancelling dispatch requests, accepting dispatches
             from the dashboard.
    """
    message = 'This action requires a Dispatcher or Admin role.'

    def has_permission(self, request, view):
        return _role(request) in DISPATCHER_ROLES


class IsDriver(permissions.BasePermission):
    """
    Grants access only to the DRIVER role.

    Matrix: TELEMETRY → Send (Driver owns GPS submission).
    Used on: duty toggle, GPS submission, driver-specific /me/ endpoints.
    Note: driver endpoints that fetch their own data (GET /api/drivers/me/)
    are intentionally left with IsAuthenticated because the view itself
    does the driver-ownership lookup.
    """
    message = 'This action is restricted to Drivers.'

    def has_permission(self, request, view):
        return _role(request) == DRIVER_ROLE


class IsDriverOrAdmin(permissions.BasePermission):
    """
    Grants access to DRIVER and both Admin tiers.

    Used on: dispatch accept (driver *and* dispatcher can accept — first wins),
             issue reporting (driver files, admin resolves).
    """
    message = 'This action requires a Driver or Admin role.'

    def has_permission(self, request, view):
        role = _role(request)
        return role in ADMIN_ROLES or role == DRIVER_ROLE


class IsViewerOrHigher(permissions.BasePermission):
    """
    Grants read-only access to any user that has a profile with a known role.

    Matrix: FLEET → View, DISPATCH → View, TELEMETRY → View (Viewer row).
    Combine with SAFE_METHODS check in get_permissions() when a view needs
    read=Viewer but write=Admin.
    """
    message = 'A valid user profile is required to access this resource.'

    def has_permission(self, request, view):
        return _role(request) in ALL_ROLES


class ReadOnlyOrAdmin(permissions.BasePermission):
    """
    Composite: safe (GET/HEAD/OPTIONS) requests → Viewer or higher.
                write (POST/PUT/PATCH/DELETE) requests → Admin only.

    Drop-in for views where Viewer can read but only Admin can write
    (e.g. Fleet and Maintenance management).
    """
    message = 'Write operations require an Admin role.'

    def has_permission(self, request, view):
        if request.method in permissions.SAFE_METHODS:
            return _role(request) in ALL_ROLES
        return _role(request) in ADMIN_ROLES


class ReadOnlyOrDispatcher(permissions.BasePermission):
    """
    Composite: safe requests → Viewer or higher.
               write requests → Dispatcher or Admin.

    Used on: dispatch list (everyone can read), create/cancel (Dispatcher+).
    """
    message = 'Creating or modifying dispatches requires a Dispatcher or Admin role.'

    def has_permission(self, request, view):
        if request.method in permissions.SAFE_METHODS:
            return _role(request) in ALL_ROLES
        return _role(request) in DISPATCHER_ROLES
