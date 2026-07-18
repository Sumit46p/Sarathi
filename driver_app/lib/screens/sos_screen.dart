import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen> with SingleTickerProviderStateMixin {
  Position? _position;
  bool _loading = true;
  String? _errorMsg;
  bool _sosTriggered = false;
  final _mapController = MapController();

  // Fills up while the SOS button is held; completing it places the call.
  late final AnimationController _holdController;

  // Central emergency number dialled by the big SOS button.
  static const String _emergencyNumber = 'tel:112';

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _triggerEmergencyCall();
        }
      });
    _fetchLocationAndSendSOS();
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  // ── Firebase + GPS (unchanged) ────────────────────────────────────────────
  Future<void> _fetchLocationAndSendSOS() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loading = false;
          _errorMsg = 'Location services are disabled. Please enable GPS.';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _loading = false;
            _errorMsg = 'Location permission denied.';
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _loading = false;
          _errorMsg = 'Location permission permanently denied.';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('emergencies').add({
        'driverId': uid,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
      });
      if (uid != null) {
        await FirebaseFirestore.instance.collection('drivers').doc(uid).update({'status': 'SOS'});
      }
      if (mounted) setState(() { _position = pos; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorMsg = e.toString(); });
    }
  }

  // ── Hold-to-call ──────────────────────────────────────────────────────────
  void _onHoldStart(_) {
    HapticFeedback.mediumImpact();
    setState(() => _sosTriggered = true);
    _holdController.forward(from: 0);
  }

  void _onHoldEnd(_) {
    if (_holdController.isCompleted) return;
    setState(() => _sosTriggered = false);
    _holdController.reverse();
  }

  Future<void> _triggerEmergencyCall() async {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _sosTriggered = false);
    await _launchPhone(_emergencyNumber, label: 'Emergency');
    if (mounted) _holdController.value = 0;
  }

  Future<void> _launchPhone(String uri, {required String label}) async {
    try {
      final launched = await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        _showSnack('Could not start call to $label.', isError: true);
      }
    } catch (_) {
      if (mounted) _showSnack('Could not start call to $label.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.plusJakartaSans(color: Colors.white)),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.secondaryColor,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? _buildLoading()
                : _errorMsg != null
                    ? _buildError()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
            ),
          ),
          Expanded(
            child: Text(
              'SOS Emergency',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.errorColor),
          const SizedBox(height: 20),
          Text('Getting your location...',
              style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppTheme.outline)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration:
                  BoxDecoration(color: AppTheme.errorColor.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.location_off_rounded, size: 40, color: AppTheme.errorColor),
            ),
            const SizedBox(height: 20),
            Text(_errorMsg!,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppTheme.onSurface)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: () {
                setState(() {
                  _loading = true;
                  _errorMsg = null;
                });
                _fetchLocationAndSendSOS();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        children: [
          // SOS button card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLowest,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onLongPressStart: _onHoldStart,
                  onLongPressEnd: _onHoldEnd,
                  onLongPressCancel: () => _onHoldEnd(null),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing outer ring
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.95, end: 1.0),
                        duration: const Duration(milliseconds: 1000),
                        builder: (_, v, child) => Transform.scale(scale: v, child: child),
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.errorContainer, width: 8),
                          ),
                        ),
                      ),
                      // Hold-to-confirm progress ring
                      AnimatedBuilder(
                        animation: _holdController,
                        builder: (_, __) => SizedBox(
                          width: 204,
                          height: 204,
                          child: CircularProgressIndicator(
                            value: _holdController.value,
                            strokeWidth: 6,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.errorColor.withValues(alpha: _sosTriggered ? 0.6 : 0.3),
                              blurRadius: _sosTriggered ? 40 : 20,
                              spreadRadius: _sosTriggered ? 10 : 0,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sos, size: 60, color: Colors.white),
                            const SizedBox(height: 8),
                            Text(
                              'HOLD TO CALL\nEMERGENCY',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // GPS status
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('LIVE GPS TRACKING ACTIVE',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.errorColor, letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Your location is being shared with dispatch.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Contacts section
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Primary Contacts',
                style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          ),
          const SizedBox(height: 12),
          _contactCard(
            icon: Icons.support_agent_rounded,
            label: 'Fleet Manager',
            subtitle: 'Direct Dispatch Line',
            color: AppTheme.primaryColor,
            phone: 'tel:123',
          ),
          const SizedBox(height: 10),
          _contactCard(
            icon: Icons.build_circle_rounded,
            label: 'Roadside Assistance',
            subtitle: 'Towing & Repair',
            color: AppTheme.secondaryColor,
            phone: 'tel:456',
          ),
          const SizedBox(height: 10),
          _contactCard(
            icon: Icons.local_police_rounded,
            label: 'Local Police',
            subtitle: 'Emergency Response',
            color: AppTheme.errorColor,
            phone: 'tel:911',
          ),
          const SizedBox(height: 24),

          // Map preview
          if (_position != null) _buildMapSection(),
        ],
      ),
    );
  }

  Widget _contactCard(
      {required IconData icon,
      required String label,
      required String subtitle,
      required Color color,
      required String phone}) {
    return GestureDetector(
      onTap: () => _launchPhone(phone, label: label),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _launchPhone(phone, label: label),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
                child: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    final center = LatLng(_position!.latitude, _position!.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 15.0),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.company.sarthi'),
                MarkerLayer(markers: [
                  Marker(
                    point: center,
                    width: 60,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                          color: AppTheme.errorColor,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppTheme.errorColor.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 4)]),
                      child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ]),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('drivers').where('status', isEqualTo: 'On Duty (Available)').snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const MarkerLayer(markers: []);
                    final markers = snap.data!.docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return data['latitude'] != null && data['longitude'] != null;
                    }).map((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return Marker(
                        point: LatLng(data['latitude'] as double, data['longitude'] as double),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.directions_car_rounded, color: AppTheme.secondaryColor, size: 30),
                      );
                    }).toList();
                    return MarkerLayer(markers: markers);
                  },
                ),
              ],
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(100)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.primaryColor),
                    const SizedBox(width: 4),
                    Text('${_position!.latitude.toStringAsFixed(4)}° N, ${_position!.longitude.toStringAsFixed(4)}° E',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.onSurface, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}