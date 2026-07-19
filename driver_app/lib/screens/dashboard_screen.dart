import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../theme.dart';
import '../widgets/action_button.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'trips_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

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
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _isAvailable = value);

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission denied. Enable it in app settings.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _sendLocationUpdate() async {
    if (!_isAvailable) return;

    final vehicle = _driverData?['assigned_vehicle'] as Map<String, dynamic>?;
    final vehicleId = vehicle?['id'];
    if (vehicleId == null) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _lastLocationStatus = 'Location services disabled');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _lastLocationStatus = 'Location permission denied');
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
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

      if (mounted) {
        setState(() {
          _lastLocationStatus = success
              ? 'Location updated ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}'
              : 'Location update failed';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastLocationStatus = 'Location error: $e');
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
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive)
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 4), decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(2)))
            else
              const SizedBox(height: 8),
            AnimatedScale(scale: isActive ? 1.1 : 1.0, duration: const Duration(milliseconds: 200), child: Icon(isActive ? item.activeIcon : item.icon, color: isActive ? AppTheme.primaryColor : AppTheme.outline, size: 24)),
            const SizedBox(height: 2),
            Text(item.label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? AppTheme.primaryColor : AppTheme.outline, letterSpacing: 0.3)),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              Text(_errorMsg!, textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _loadProfile, icon: const Icon(Icons.refresh_rounded), label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)), style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white)),
            ],
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
                 _buildVehicleCard(vehicleName, vehicleType, plate),
                const SizedBox(height: 24),
                _buildDutyToggle(),
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
                _buildQuickActionsSection(),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.power_settings_new_rounded, color: _isAvailable ? AppTheme.secondaryColor : AppTheme.outline, size: 22),
              const SizedBox(width: 12),
              Text('On Duty', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            ],
          ),
          Switch(
            value: _isAvailable,
            onChanged: _toggleAvailability,
            activeColor: Colors.white,
            activeTrackColor: AppTheme.secondaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.flash_on_rounded, size: 16, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 10),
            Text('Quick Actions', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ActionButton(label: 'SOS\nHelp', icon: Icons.emergency_share_rounded, color: AppTheme.errorColor, onTap: () {}),
            ActionButton(label: 'Fuel\nEntry', icon: Icons.local_gas_station_rounded, color: AppTheme.primaryColor, onTap: () {}),
            ActionButton(label: 'Report\nIssue', icon: Icons.build_circle_rounded, color: const Color(0xFF7C3AED), onTap: () {}),
            ActionButton(label: 'Inspect\nVehicle', icon: Icons.fact_check_rounded, color: AppTheme.tertiaryColor, onTap: () {}),
          ],
        ),
      ],
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
