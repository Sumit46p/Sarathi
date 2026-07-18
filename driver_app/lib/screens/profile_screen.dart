import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  bool _uploadingImage = false;

  // ── Firebase logic (unchanged) ────────────────────────────────────────────
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            Container(height: 4, width: 40, margin: const EdgeInsets.symmetric(horizontal: 180, vertical: 12), decoration: BoxDecoration(color: AppTheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            ListTile(leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primaryColor), title: Text('Camera', style: GoogleFonts.plusJakartaSans()), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primaryColor), title: Text('Gallery', style: GoogleFonts.plusJakartaSans()), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked == null) return;
    setState(() => _uploadingImage = true);
    try {
      final ref = FirebaseStorage.instance.ref().child('driver_profiles/$_uid/avatar.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('drivers').doc(_uid).update({'profileImageUrl': url});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated!'), backgroundColor: AppTheme.secondaryColor));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppTheme.errorColor));
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('drivers').doc(_uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Something went wrong loading your profile:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor),
                ),
              ),
            );
          }
          if (_uid == null) {
            return Center(
              child: Text('You need to be signed in to view your profile.', style: GoogleFonts.plusJakartaSans()),
            );
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('Profile not found.', style: GoogleFonts.plusJakartaSans()));
          }
          final data     = snapshot.data!.data() as Map<String, dynamic>;

          try {
            final name     = (data['name'] ?? 'Driver').toString();
            final vehicle  = (data['vehicleNumber'] ?? '').toString();
            final status   = (data['status'] ?? 'Off Duty').toString();
            final imageUrl = data['profileImageUrl']?.toString();
            final totalTrips = (data['totalTrips'] ?? 0).toString();

            // Everything captured during signup — shown read-only further down.
            // NOTE: these keys are my best guess based on common driver-signup
            // fields (name/vehicle/status already existed in your data). If your
            // signup form uses different field names, share that screen and I'll
            // wire these up to match exactly.
            final signupFields = <_InfoField>[
              _InfoField('Full Name', data['name'], Icons.badge_rounded),
              _InfoField('Email Address', data['email'], Icons.email_rounded),
              _InfoField('Phone Number', data['phone'] ?? data['phoneNumber'], Icons.phone_rounded),
              _InfoField('Vehicle Number', data['vehicleNumber'], Icons.local_taxi_rounded),
              _InfoField('Vehicle Type', data['vehicleType'], Icons.directions_car_filled_rounded),
              _InfoField('License Number', data['licenseNumber'], Icons.card_membership_rounded),
              _InfoField('Address', data['address'], Icons.home_rounded),
              _InfoField('Emergency Contact', data['emergencyContact'], Icons.contact_phone_rounded),
            ];

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  _buildHeader(),
                  _buildHeroSection(name, imageUrl, status),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: Column(
                      children: [
                        // Quick stats
                        Row(
                          children: [
                            Expanded(child: _quickStat('Total Trips', totalTrips, AppTheme.primaryColor)),
                            const SizedBox(width: 12),
                            Expanded(child: _quickStat('Rating', '—', AppTheme.secondaryColor)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Settings list
                        _settingsTile(icon: Icons.manage_accounts_rounded, color: AppTheme.primaryColor, label: 'Personal Information', subtitle: 'Manage your details', onTap: () {}),
                        const SizedBox(height: 10),
                        _settingsTile(icon: Icons.local_shipping_rounded, color: AppTheme.secondaryColor, label: 'Vehicle Details', subtitle: vehicle.isEmpty ? '—' : vehicle, onTap: () {}),
                        const SizedBox(height: 10),
                        _settingsTile(
                          icon: Icons.description_rounded, color: AppTheme.tertiaryColor,
                          label: 'Documents & Licenses', subtitle: 'KYC and License status', onTap: () {},
                          badge: 'Verified',
                        ),
                        const SizedBox(height: 10),
                        _settingsTile(icon: Icons.settings_rounded, color: AppTheme.onSurfaceVariant, label: 'Settings', subtitle: 'Notifications and security', onTap: () {}),
                        const SizedBox(height: 24),

                        // Signup information
                        _buildInfoSection(signupFields),
                        const SizedBox(height: 20),

                        // Logout
                        _logoutTile(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } catch (e) {
            // Something in the profile data made a widget throw. Show the
            // error instead of a blank screen, and keep logout reachable.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.errorColor),
                    const SizedBox(height: 16),
                    Text(
                      'Something went wrong showing your profile:\n$e',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    _logoutTile(),
                  ],
                ),
              ),
            );
          }
        },
      ),
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
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.person_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 10),
              Text('Sarathi', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          IconButton(icon: const Icon(Icons.notifications_active_rounded, color: Colors.white), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildHeroSection(String name, String? imageUrl, String status) {
    return Transform.translate(
      offset: const Offset(0, -40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            // Avatar — tap to upload/change your photo
            GestureDetector(
              onTap: _pickAndUploadImage,
              child: Stack(
                children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: ClipOval(
                      child: imageUrl != null
                          ? Image.network(imageUrl, fit: BoxFit.cover, width: 110, height: 110)
                          : Container(color: AppTheme.surfaceContainer, child: _uploadingImage
                              ? const CircularProgressIndicator(color: AppTheme.primaryColor)
                              : const Icon(Icons.person_rounded, size: 52, color: AppTheme.primaryColor)),
                    ),
                  ),
                  Positioned(
                    bottom: 2, right: 2,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ],
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
                Text('Driver ID: —', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _quickStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _settingsTile({required IconData icon, required Color color, required String label, required String subtitle, required VoidCallback onTap, String? badge}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLowest,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.secondaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(100)),
                          child: Text(badge, style: GoogleFonts.plusJakartaSans(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor, letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.outline, size: 22),
          ],
        ),
      ),
    );
  }

  // ── Signup information section ──────────────────────────────────────────
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Text('Everything you shared with us when you signed up.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline)),
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
}

// ── Small helper for rendering signup fields ────────────────────────────────
class _InfoField {
  final String label;
  final dynamic value;
  final IconData icon;
  const _InfoField(this.label, this.value, this.icon);
}