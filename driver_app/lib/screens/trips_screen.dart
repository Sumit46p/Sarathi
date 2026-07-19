import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  Map<String, dynamic>? _dispatch;
  bool _loading = true;
  String? _errorMsg;
  bool _transitioning = false;
  Timer? _pollTimer;

  static const Map<String, List<String>> _validTransitions = {
    'assigned': ['accepted', 'cancelled'],
    'accepted': ['en_route', 'cancelled'],
    'en_route': ['arrived', 'cancelled'],
    'arrived': ['completed', 'cancelled'],
  };

  static const Map<String, String> _statusLabels = {
    'assigned': 'Assigned',
    'accepted': 'Accepted',
    'en_route': 'En Route',
    'arrived': 'Arrived',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
  };

  @override
  void initState() {
    super.initState();
    _loadDispatch();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadDispatch(showLoading: false));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDispatch({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    final data = await ApiService.getMyDispatch();
    if (!mounted) return;
    setState(() {
      _dispatch = data;
      _loading = false;
      _errorMsg = data == null ? null : _errorMsg;
    });
  }

  List<LatLng> _decodeGeometry(dynamic geometry) {
    if (geometry is! List) return [];
    final points = <LatLng>[];
    for (final p in geometry) {
      if (p is List && p.length >= 2) {
        final lat = (p[0] as num?)?.toDouble();
        final lng = (p[1] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  Future<void> _transition(String next) async {
    setState(() => _transitioning = true);
    final result = await ApiService.transitionDispatch(status: next);
    if (!mounted) return;
    setState(() => _transitioning = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update trip'), backgroundColor: Colors.red),
      );
    } else {
      setState(() => _dispatch = result);
    }
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, size: 48, color: AppTheme.outline),
            const SizedBox(height: 16),
            Text('No active trip', style: GoogleFonts.plusJakartaSans(fontSize: 16, color: AppTheme.outline)),
            const SizedBox(height: 6),
            Text('You will be notified here when dispatched.', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline)),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final requestLat = (_dispatch?['request_lat'] as num?)?.toDouble();
    final requestLng = (_dispatch?['request_lng'] as num?)?.toDouble();
    final route = _decodeGeometry(_dispatch?['geometry']);

    LatLng center;
    if (route.isNotEmpty) {
      center = route.first;
    } else if (requestLat != null && requestLng != null) {
      center = LatLng(requestLat, requestLng);
    } else {
      center = const LatLng(27.7, 85.3);
    }

    final markers = <Marker>[];
    if (requestLat != null && requestLng != null) {
      markers.add(
        Marker(
          point: LatLng(requestLat, requestLng),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: Colors.red, size: 36),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.company.sarthi',
        ),
        if (route.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(points: route, strokeWidth: 5, color: AppTheme.primaryColor),
            ],
          ),
        if (markers.isNotEmpty)
          MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildActionButton(String next) {
    final label = _statusLabels[next] ?? next;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: _transitioning ? null : () => _transition(next),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = _dispatch?['status'] as String?;
    final vehicleName = _dispatch?['assigned_vehicle_name'] as String? ?? 'Vehicle';
    final distance = (_dispatch?['distance_km'] as num?)?.toStringAsFixed(1);
    final duration = (_dispatch?['duration_min'] as num?)?.toStringAsFixed(0);
    final nextSteps = (currentStatus != null ? _validTransitions[currentStatus] : null) ?? [];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Trips', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _dispatch == null
              ? _buildEmpty()
              : Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildMap(),
                    ),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Active Trip', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _statusLabels[currentStatus] ?? currentStatus ?? '',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(vehicleName, style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppTheme.outline)),
                            if (distance != null || duration != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (distance != null) '$distance km',
                                  if (duration != null) '~$duration min',
                                ].join('  •  '),
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (nextSteps.isNotEmpty) ...[
                              Text('Update status', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                              const SizedBox(height: 12),
                              Row(
                                children: nextSteps.map(_buildActionButton).toList(),
                              ),
                            ] else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceLowest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  currentStatus == 'completed'
                                      ? 'Trip completed. Great work!'
                                      : 'No further action required.',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
