import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'trips_screen.dart';
import 'report_issue_screen.dart';
import 'fuel_entry_screen.dart';
import 'trip_history_screen.dart';
import 'maintenance_screen.dart';

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
  bool _isOnDuty = false;
  Timer? _locationTimer;
  String? _lastLocationStatus;
  int _consecutiveLocationFailures = 0;
  StreamSubscription<void>? _forceLogoutSub;
  Timer? _notificationTimer;
  int _unreadNotifications = 0;
  int _notificationFailures = 0;
  final AudioPlayer _notificationPlayer = AudioPlayer();
  final Set<String> _beepedNotificationIds = <String>{};

  @override
  void initState() {
    super.initState();
    _forceLogoutSub = forceLogoutController.stream.listen((_) {
      if (mounted) _performLogout();
    });
    _loadProfile();
    _startNotificationPolling();
  }

  void _startNotificationPolling() {
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final notifications = await ApiService.getNotifications();
        if (!mounted) return;
        _notificationFailures = 0;
        final unread = notifications.where((n) => n['read'] == false).length;
        
        final newNotificationIds = notifications
            .where((n) {
              final id = n['id']?.toString();
              return n['read'] == false && id != null && !_beepedNotificationIds.contains(id);
            })
            .map((n) => n['id']!.toString())
            .toSet();
        
        if (newNotificationIds.isNotEmpty) {
          HapticFeedback.heavyImpact();
          try {
            await _notificationPlayer.play(AssetSource('sounds/notification.mp3'));
          } catch (e) {
            // Ignore sound playback errors
          }
          _beepedNotificationIds.addAll(newNotificationIds);
        }
        
        setState(() {
          _unreadNotifications = unread;
        });
      } catch (e) {
        _notificationFailures++;
        if (_notificationFailures >= 3) {
          ApiService.resetBaseUrl();
          _notificationFailures = 0;
        }
      }
    });
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
        _isOnDuty = isOnDuty;
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
            title: Text('Change Password', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You must change your password before continuing.', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
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
                    : Text('Update Password', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleDutyStatus(bool value) async {
    if (value) {
      final hasLocationPermission = await _validateLocationBeforeDuty();
      if (!hasLocationPermission) {
        if (mounted) setState(() => _isOnDuty = false);
        return;
      }
    }

    setState(() => _isOnDuty = value);

    try {
      final result = await ApiService.setDutyStatus(isOnDuty: value);

      if (result == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update status'), backgroundColor: AppTheme.errorColor),
        );
        setState(() => _isOnDuty = !value);
        return;
      }

      if (mounted) {
        setState(() {
          _isOnDuty = result?['is_on_duty'] == true;
          _driverData = result ?? _driverData;
        });
      }

      if (_isOnDuty) {
        _startLocationTracking();
      } else {
        _stopLocationTracking();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: ${e.message}'), backgroundColor: AppTheme.errorColor),
        );
        setState(() => _isOnDuty = !value);
      }
    }
  }

  Future<bool> _validateLocationBeforeDuty() async {
    if (!mounted) return false;
    
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location services must be enabled to go on duty'),
            backgroundColor: AppTheme.errorColor,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showLocationPermissionDeniedDialog();
      }
      return false;
    }
    
    if (permission != LocationPermission.whileInUse && 
        permission != LocationPermission.always) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to go on duty'),
            backgroundColor: AppTheme.errorColor,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _ensureLocationPermission() async {
    if (!mounted) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services to go on duty'),
            backgroundColor: AppTheme.errorColor,
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
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        content: Text(
          'On Duty mode requires location access to send your position updates. '
          'Please enable location permission in your device settings.',
          style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500, color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings_rounded, size: 18),
            label: Text('Open Settings',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
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
    if (!_isOnDuty) return;

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
    _notificationTimer?.cancel();
    _forceLogoutSub?.cancel();
    _notificationPlayer.dispose();
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

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      _buildHomeBody(),
      const TripsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading && _selectedIndex == 0 ? _buildLoading() : screens[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildLoading() {
    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, Icons.home_rounded, 'Home', 0),
              _buildNavItem(Icons.map_outlined, Icons.map_rounded, 'Trips', 1),
              _buildNavItem(Icons.person_outline, Icons.person_rounded, 'Profile', 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, IconData activeIcon, String label, int index) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? activeIcon : icon,
            color: isActive ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: isActive ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBody() {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.errorColor),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ApiService.resetBaseUrl();
                  _loadProfile();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _performLogout();
                },
                icon: const Icon(Icons.logout_rounded),
                label: Text('Log Out', style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: AppTheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      );
    }

    final vehicle = _driverData?['assigned_vehicle'] as Map<String, dynamic>?;
    final vehicleName = vehicle?['name']?.toString() ?? 'Not assigned';
    final vehicleType = vehicle?['vehicle_type']?.toString() ?? '—';
    final plate = vehicle?['number_plate']?.toString() ?? '—';

    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.dashboard_outlined, color: AppTheme.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Dashboard',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Current Status Toggle
            _buildStatusToggle(),
            const SizedBox(height: 16),

            // Assigned Vehicle Card
            _buildVehicleCard(vehicleName, vehicleType, plate),
            const SizedBox(height: 24),

            // Quick Actions
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CURRENT STATUS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isOnDuty ? 'On Duty' : 'Off Duty',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurface,
                ),
              ),
            ],
          ),
          Switch(
            value: _isOnDuty,
            onChanged: (value) {
              HapticFeedback.mediumImpact();
              _toggleDutyStatus(value);
            },
            activeColor: Colors.white,
            activeTrackColor: AppTheme.successColor,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppTheme.outline,
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(String name, String type, String plate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ASSIGNED VEHICLE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isOnDuty ? AppTheme.successLight : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isOnDuty ? 'On Duty' : 'Off Duty',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _isOnDuty ? AppTheme.successColor : AppTheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_shipping_outlined,
                  color: AppTheme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plate,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Report',
                Icons.report_problem_outlined,
                AppTheme.errorColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportIssueScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'Fuel',
                Icons.local_gas_station_outlined,
                AppTheme.primaryColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FuelEntryScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'History',
                Icons.history_outlined,
                AppTheme.secondaryColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TripHistoryScreen()),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Emergency Section
        _buildEmergencySection(),
        const SizedBox(height: 24),

        // Maintenance Section
        _buildMaintenanceSection(),
        const SizedBox(height: 24),
        
        
        // No Active Trips Section
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: AppTheme.onSurfaceVariant,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No Active Trips',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Switch to On Duty to start receiving emergency dispatch requests.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaintenanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maintenance',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Request',
                Icons.build_outlined,
                AppTheme.primaryColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'History',
                Icons.history_outlined,
                AppTheme.secondaryColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MaintenanceScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmergencySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Emergency',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Dispatch',
                Icons.emergency_outlined,
                AppTheme.errorColor,
                () async {
                  HapticFeedback.lightImpact();
                  final dispatch = await ApiService.getMyDispatch();
                  if (dispatch != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TripsScreen()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No active emergency dispatch'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                'Report',
                Icons.report_problem_outlined,
                AppTheme.errorColor,
                () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportIssueScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}