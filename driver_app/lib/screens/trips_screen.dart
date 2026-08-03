import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    try {
      final data = await ApiService.getMyDispatch();
      if (!mounted) return;
      setState(() {
        _dispatch = data;
        _loading = false;
        _errorMsg = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.kind == ApiErrorKind.network) {
          _errorMsg = 'Network error. Please check your connection and retry.';
        } else if (e.kind == ApiErrorKind.unauthorized) {
          _errorMsg = 'Session expired. Please log in again.';
        } else {
          _errorMsg = 'Failed to load trip: ${e.message}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'An unexpected error occurred.';
      });
    }
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
        const SnackBar(content: Text('Failed to update trip'), backgroundColor: AppTheme.errorColor),
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.map_outlined,
                size: 40,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Active Trip',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You will be notified here when dispatched.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
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
          child: const Icon(Icons.location_on, color: AppTheme.errorColor, size: 36),
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
    final isCancel = next == 'cancelled';
    
    return Expanded(
      child: ElevatedButton(
        onPressed: _transitioning
            ? null
            : () {
                HapticFeedback.mediumImpact();
                _transition(next);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isCancel ? AppTheme.errorColor : AppTheme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _transitioning
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.errorColor),
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
                _loadDispatch();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
            : _errorMsg != null && _dispatch == null
                ? _buildError()
                : _dispatch == null
                    ? _buildEmpty()
                    : Column(
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.map_outlined, color: AppTheme.primaryColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Active Trip',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Map
                          Expanded(
                            flex: 2,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.outlineVariant),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildMap(),
                            ),
                          ),
                          
                          // Trip Details
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Status Badge
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Trip Status',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: const BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _statusLabels[currentStatus] ?? currentStatus ?? '',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  
                                  // Vehicle Info
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: AppTheme.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(
                                            Icons.local_shipping_outlined,
                                            color: AppTheme.primaryColor,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                vehicleName,
                                                style: GoogleFonts.inter(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppTheme.onSurface,
                                                ),
                                              ),
                                              if (distance != null || duration != null)
                                                Text(
                                                  '${distance ?? '--'} km • ${duration ?? '--'} min',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: AppTheme.onSurfaceVariant,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  
                                  // Action Buttons
                                  if (nextSteps.isNotEmpty) ...[
                                    Text(
                                      'Update Status',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: nextSteps.map(_buildActionButton).toList(),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: currentStatus == 'completed'
                                            ? AppTheme.successLight
                                            : AppTheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            currentStatus == 'completed'
                                                ? Icons.check_circle_rounded
                                                : Icons.info_outline_rounded,
                                            color: currentStatus == 'completed'
                                                ? AppTheme.successColor
                                                : AppTheme.onSurfaceVariant,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              currentStatus == 'completed'
                                                  ? 'Trip completed. Great work!'
                                                  : 'No further action required.',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: currentStatus == 'completed'
                                                    ? AppTheme.successColor
                                                    : AppTheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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