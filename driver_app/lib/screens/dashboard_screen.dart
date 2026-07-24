import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../theme.dart';
import '../widgets/action_button.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'trips_screen.dart';
import 'report_issue_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _driverData;
  bool _loading = true;
  String? _errorMsg;
  bool _isAvailable = true;
  Timer? _locationTimer;
  String? _lastLocationStatus;
  int _consecutiveLocationFailures = 0;
  StreamSubscription<void>? _forceLogoutSub;

  @override
  void initState() {
    super.initState();
    _forceLogoutSub = forceLogoutController.stream.listen((_) {
      if (mounted) _performLogout();
    });
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final data = await ApiService.getDriverMe();
      if (!mounted) return;

      bool isOnDuty = false;
      if (data != null) {
        isOnDuty = data['is_on_duty'] == true;
      }

      setState(() {
        _driverData = data;
        _loading = false;
        _isAvailable = isOnDuty;
        if (data == null) {
          _errorMsg = 'Failed to load profile. Please log in again.';
        }
      });

      if (isOnDuty) {
        await _ensureLocationPermission();
        _startLocationTracking();
      }

      if (data?['requires_password_change'] == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPasswordChangeDialog();
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiErrorKind.unauthorized) {
        // Token is invalid/expired - clear it and redirect to login
        await _performLogout();
      } else {
        setState(() {
          _loading = false;
          if (e.kind == ApiErrorKind.network) {
            _errorMsg = 'Network error. Please check your connection and retry.';
          } else {
            _errorMsg = 'Failed to load profile: ${e.message}';
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'An unexpected error occurred. Please retry.';
      });
    }
  }

  void _showPasswordChangeDialog() {
    final passwordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Change Password', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You must change your password before continuing.', style: GoogleFonts.plusJakartaSans(color: AppTheme.outline)),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    errorText: errorMessage,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () async {
                  final newPassword = passwordController.text;
                  if (newPassword.length < 6) {
                    setDialogState(() => errorMessage = 'Must be at least 6 characters');
                    return;
                  }
                  setDialogState(() {
                    isLoading = true;
                    errorMessage = null;
                  });
                  final success = await ApiService.changePassword(newPassword);
                  if (success) {
                    if (mounted) Navigator.of(ctx).pop();
                  } else {
                    setDialogState(() {
                      isLoading = false;
                      errorMessage = 'Failed to change password.';
                    });
                  }
                },
                child: isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Update Password', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _isAvailable = value);

    try {
      final result = await ApiService.setDutyStatus(isOnDuty: value);

      if (result == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status'), backgroundColor: Colors.red),
        );
        setState(() => _isAvailable = !value);
        return;
      }

      if (mounted) {
        setState(() {
          _isAvailable = result?['is_on_duty'] == true;
          _driverData = result ?? _driverData;
        });
      }

      if (_isAvailable) {
        await _ensureLocationPermission();
        _startLocationTracking();
      } else {
        _stopLocationTracking();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: ${e.message}'), backgroundColor: Colors.red),
        );
        setState(() => _isAvailable = !value);
      }
    }
  }

  Future<void> _ensureLocationPermission() async {
    if (!mounted) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services to go on duty'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      _showLocationPermissionDeniedDialog();
    }
  }

  void _showLocationPermissionDeniedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Location Permission Required',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'On Duty mode requires location access to send your position updates. '
          'Please enable location permission in your device settings.',
          style: GoogleFonts.plusJakartaSans(color: AppTheme.outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600, color: AppTheme.outline)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: Text('Open Settings',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendLocationUpdate() async {
    if (!_isAvailable) return;

    final vehicle = _driverData?['assigned_vehicle'] as Map<String, dynamic>?;
    final vehicleId = vehicle?['id'];
    if (vehicleId == null) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _consecutiveLocationFailures++;
        if (mounted && _consecutiveLocationFailures >= 6) {
          setState(() => _lastLocationStatus = 'Location services disabled');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _consecutiveLocationFailures++;
          if (mounted && _consecutiveLocationFailures >= 6) {
            setState(() => _lastLocationStatus = 'Location permission denied');
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _consecutiveLocationFailures++;
        if (mounted && _consecutiveLocationFailures >= 6) {
          setState(() => _lastLocationStatus = 'Location permission permanently denied');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final success = await ApiService.updateLocation(
        vehicleId: vehicleId as int,
        lat: position.latitude,
        lng: position.longitude,
      );

      if (success) {
        _consecutiveLocationFailures = 0;
      } else {
        _consecutiveLocationFailures++;
      }

      if (mounted) {
        setState(() {
          _lastLocationStatus = success
              ? 'Location updated ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}'
              : (_consecutiveLocationFailures >= 6 ? 'Location update failed — check connection' : null);
        });
      }
    } catch (e) {
      _consecutiveLocationFailures++;
      // Only surface the error after ~30s of continuous failures (6 × 5s intervals).
      if (mounted && _consecutiveLocationFailures >= 6) {
        setState(() => _lastLocationStatus = 'Location error — retrying in background');
      }
    }
  }

  void _startLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendLocationUpdate();
    });
    _sendLocationUpdate();
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _forceLogoutSub?.cancel();
    super.dispose();
  }

  Future<void> _performLogout() async {
    await ApiService.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to log out of your account?', style: GoogleFonts.plusJakartaSans(color: AppTheme.outline)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppTheme.outline))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('Logout', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppTheme.errorColor))),
        ],
      ),
    );

    if (confirmed == true) {
      await _performLogout();
    }
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      _buildHomeBody(),
      const TripsScreen(),
      _buildAlertsBody(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading ? _buildLoading() : screens[_selectedIndex],
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildLoading() {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
    );
  }

  Widget _buildBottomBar() {
    const items = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
      _NavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Trips'),
      _NavItem(icon: Icons.notifications_none_rounded, activeIcon: Icons.notifications_active_rounded, label: 'Alerts'),
      _NavItem(icon: Icons.sentiment_satisfied_alt_outlined, activeIcon: Icons.sentiment_satisfied_alt_rounded, label: 'Me'),
    ];

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < items.length; i++) _buildNavItem(items[i], i),
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _onItemTapped(index);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: isActive ? 40 : 0,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (!isActive) const SizedBox(height: 8),
            AnimatedScale(
              scale: isActive ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                letterSpacing: 0.3,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeBody() {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedListItem(
            index: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.errorColor),
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMsg!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _loadProfile();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final name = (_driverData?['name'] ?? 'Driver').toString();
    final firstName = name.split(' ').first;
    final vehicle = _driverData?['assigned_vehicle'] as Map<String, dynamic>?;
    final vehicleName = vehicle?['name'] ?? 'Not assigned';
    final vehicleType = vehicle?['vehicle_type'] ?? '—';
    final plate = vehicle?['number_plate'] ?? '—';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildTopHeader(firstName),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedListItem(
                  index: 0,
                  delay: const Duration(milliseconds: 80),
                  child: _buildVehicleCard(vehicleName, vehicleType, plate),
                ),
                const SizedBox(height: 24),
                AnimatedListItem(
                  index: 1,
                  delay: const Duration(milliseconds: 80),
                  child: _buildDutyToggle(),
                ),
                if (_isAvailable && _lastLocationStatus != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _lastLocationStatus!,
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.outline),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                AnimatedListItem(
                  index: 2,
                  delay: const Duration(milliseconds: 80),
                  child: _buildQuickActionsSection(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(String firstName) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Container(
        width: double.infinity,
        color: AppTheme.primaryColor,
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 48),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_people_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getGreeting(firstName), style: GoogleFonts.plusJakartaSans(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 3),
                  if (_driverData?['organization_name'] != null || _driverData?['organization'] != null)
                    Text(
                      (_driverData?['organization_name'] ?? _driverData?['organization']).toString(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, 
                        fontWeight: FontWeight.w500, 
                        color: Colors.white.withValues(alpha: 0.9)
                      ),
                    ),
                  if (_driverData?['organization_name'] != null || _driverData?['organization'] != null)
                    const SizedBox(height: 3),
                  Text(_getSubGreeting(), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: AppTheme.surfaceLowest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: _handleMenuSelection,
              itemBuilder: (ctx) => [
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout_rounded, size: 18, color: AppTheme.errorColor),
                      const SizedBox(width: 10),
                      Text('Logout', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppTheme.errorColor)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting(String name) {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning, $name! ☀️';
    if (hour < 17) return 'Good Afternoon, $name! 👋';
    return 'Good Evening, $name! 🌙';
  }

  String _getSubGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Let's make today a great one on the road.";
    if (hour < 17) return 'Hope your day is going smoothly!';
    return 'Almost done for today — drive safe!';
  }

  void _handleMenuSelection(String value) {
    if (value == 'logout') _confirmLogout();
  }

  Widget _buildVehicleCard(String name, String type, String plate) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.directions_car_rounded, size: 16, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 10),
                Text('Your Vehicle', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                      const SizedBox(height: 4),
                      Text('$type • $plate', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isAvailable ? AppTheme.secondaryColor.withValues(alpha: 0.1) : AppTheme.outline.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isAvailable ? 'Available' : 'Busy',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: _isAvailable ? AppTheme.secondaryColor : AppTheme.outline),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDutyToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_isAvailable ? AppTheme.secondaryColor : AppTheme.outline)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: _isAvailable ? AppTheme.secondaryColor : AppTheme.outline,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'On Duty',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _isAvailable ? 'Available for trips' : 'Currently offline',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppTheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Switch(
            value: _isAvailable,
            onChanged: (value) {
              HapticFeedback.mediumImpact();
              _toggleAvailability(value);
            },
            activeColor: Colors.white,
            activeTrackColor: AppTheme.secondaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    final actions = [
      _ActionData('SOS\nHelp', Icons.emergency_share_rounded, AppTheme.errorColor, _handleSOS),
      _ActionData('Fuel\nEntry', Icons.local_gas_station_rounded, AppTheme.primaryColor, () => _handleCameraAction('Fuel Entry', 'fuel')),
      _ActionData('Report\nIssue', Icons.build_circle_rounded, const Color(0xFF7C3AED), () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          SmoothPageRoute(page: const ReportIssueScreen()),
        );
      }),
      _ActionData('Inspect\nVehicle', Icons.fact_check_rounded, AppTheme.tertiaryColor, () => _handleCameraAction('Inspect Vehicle', 'inspect')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flash_on_rounded, size: 16, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 10),
            Text(
              'Quick Actions',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.7,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            return AnimatedListItem(
              index: index,
              delay: const Duration(milliseconds: 60),
              child: ActionButton(
                label: action.label,
                icon: action.icon,
                color: action.color,
                onTap: action.onTap,
              ),
            );
          },
        ),
      ],
    );
  }

  /// SOS — shows a confirmation dialog then dials emergency services.
  void _handleSOS() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.red[50],
        title: Row(
          children: [
            const Icon(Icons.emergency_share_rounded, color: Colors.red, size: 26),
            const SizedBox(width: 10),
            Text('SOS Emergency', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: Colors.red)),
          ],
        ),
        content: Text(
          'This will call emergency services (100).\nOnly use this in a real emergency.',
          style: GoogleFonts.plusJakartaSans(color: Colors.red[800]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTheme.outline, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.call_rounded, size: 18),
            label: Text('Call 100', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri(scheme: 'tel', path: '100');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open the dialler'), backgroundColor: Colors.red),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Opens camera then shows a note dialog for Fuel Entry / Report / Inspect.
  Future<void> _handleCameraAction(String title, String type) async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required for this action.'), backgroundColor: Colors.red),
      );
      if (status.isPermanentlyDenied) {
         openAppSettings();
      }
      return;
    }

    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (image == null || !mounted) return; // User cancelled

    final notesController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photo captured ✓', style: GoogleFonts.plusJakartaSans(color: Colors.green, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Add notes (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTheme.outline)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$title logged successfully'),
                    backgroundColor: AppTheme.primaryColor,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Save Log', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsBody() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Alerts', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_rounded, size: 48, color: AppTheme.outline),
              SizedBox(height: 16),
              Text('Alerts coming soon', style: TextStyle(fontSize: 16, color: AppTheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}

class _ActionData {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionData(this.label, this.icon, this.color, this.onTap);
}