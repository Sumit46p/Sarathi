import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _driverData;
  bool _loading = true;
  String? _errorMsg;

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

    setState(() {
      _driverData = data;
      _loading = false;
      if (data == null) {
        _errorMsg = 'Failed to load profile. Please try again.';
      }
    });
  }

  Future<void> _signOut() async {
    await ApiService.clearTokens();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
    }

    if (_errorMsg != null || _driverData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              Text(
                _errorMsg ?? 'Profile not found.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final name = (_driverData!['name'] ?? 'Driver').toString();
    final phone = (_driverData!['phone_number'] ?? '').toString();
    final license = (_driverData!['license_number'] ?? '').toString();
    final isActive = _driverData!['is_active'] == true;
    final vehicle = _driverData!['assigned_vehicle'] as Map<String, dynamic>?;

    final infoFields = <_InfoField>[
      _InfoField('Full Name', name, Icons.badge_rounded),
      _InfoField('Phone Number', phone.isEmpty ? '—' : phone, Icons.phone_rounded),
      _InfoField('License Number', license.isEmpty ? '—' : license, Icons.card_membership_rounded),
      _InfoField('Status', isActive ? 'Active' : 'Inactive', isActive ? Icons.check_circle_rounded : Icons.cancel_rounded),
      if (vehicle != null) ...[
        _InfoField('Vehicle', vehicle['name'] ?? '—', Icons.directions_car_rounded),
        _InfoField('Vehicle Type', (vehicle['vehicle_type'] ?? '—').toString(), Icons.local_shipping_rounded),
        _InfoField('Number Plate', (vehicle['number_plate'] ?? '—').toString(), Icons.pin_rounded),
        _InfoField('Availability', vehicle['is_available'] == true ? 'Available' : 'Unavailable', Icons.wb_sunny_rounded),
      ],
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildHeader(),
          _buildHeroSection(name),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: Column(
              children: [
                _buildInfoSection(infoFields),
                const SizedBox(height: 20),
                _logoutTile(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Text('Sarathi', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(String name) {
    return Transform.translate(
      offset: const Offset(0, -40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 6))],
              ),
              child: ClipOval(
                child: Container(
                  color: AppTheme.surfaceContainer,
                  child: const Icon(Icons.person_rounded, size: 52, color: AppTheme.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.onSurface, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.badge_rounded, size: 14, color: AppTheme.outline),
                const SizedBox(width: 4),
                Text('Driver ID: ${_driverData?['id'] ?? '—'}', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(List<_InfoField> fields) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.assignment_ind_rounded, size: 16, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 10),
              Text('Your Information', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < fields.length; i++) ...[
            _infoRow(fields[i]),
            if (i != fields.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: AppTheme.surfaceVariant.withValues(alpha: 0.4), height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(_InfoField field) {
    final hasValue = field.value != null && field.value.toString().trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppTheme.outline.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(9)),
          child: Icon(field.icon, size: 16, color: AppTheme.outline),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(field.label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.outline)),
              const SizedBox(height: 2),
              Text(
                hasValue ? field.value.toString() : '—',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hasValue ? AppTheme.onSurface : AppTheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _logoutTile() {
    return GestureDetector(
      onTap: _signOut,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.errorColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.logout_rounded, color: AppTheme.errorColor, size: 22)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Logout', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.errorColor)),
                  Text('Securely exit your account', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.errorColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.errorColor.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}

class _InfoField {
  final String label;
  final dynamic value;
  final IconData icon;
  const _InfoField(this.label, this.value, this.icon);
}
