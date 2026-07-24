import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';

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
        child: AnimatedListItem(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Transform.rotate(
                      angle: (1 - value) * 0.2,
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.route_rounded, size: 48, color: AppTheme.primaryColor),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No active trip',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You will be notified here when dispatched.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppTheme.outline,
                  height: 1.4,
                ),
              ),
            ],
          ),
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
          onPressed: _transitioning
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  _transition(next);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedListItem(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.errorColor),
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
                  _loadDispatch();
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
          : _errorMsg != null && _dispatch == null
              ? _buildError()
              : _dispatch == null
                  ? _buildEmpty()
                  : Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Hero(
                        tag: 'trip_map',
                        child: _buildMap(),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedListItem(
                              index: 0,
                              delay: const Duration(milliseconds: 100),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Active Trip',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: AppTheme.secondaryColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _statusLabels[currentStatus] ?? currentStatus ?? '',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.secondaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            AnimatedListItem(
                              index: 1,
                              delay: const Duration(milliseconds: 100),
                              child: Text(
                                vehicleName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  color: AppTheme.outline,
                                ),
                              ),
                            ),
                            if (distance != null || duration != null) ...[
                              const SizedBox(height: 6),
                              AnimatedListItem(
                                index: 2,
                                delay: const Duration(milliseconds: 100),
                                child: Row(
                                  children: [
                                    if (distance != null) ...[
                                      const Icon(Icons.route_rounded, size: 14, color: AppTheme.outline),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$distance km',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: AppTheme.outline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if (distance != null && duration != null) ...[
                                      const SizedBox(width: 12),
                                      Text('•', style: TextStyle(color: AppTheme.outline)),
                                      const SizedBox(width: 12),
                                    ],
                                    if (duration != null) ...[
                                      const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.outline),
                                      const SizedBox(width: 4),
                                      Text(
                                        '~$duration min',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: AppTheme.outline,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (nextSteps.isNotEmpty) ...[
                              AnimatedListItem(
                                index: 3,
                                delay: const Duration(milliseconds: 100),
                                child: Text(
                                  'Update status',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              AnimatedListItem(
                                index: 4,
                                delay: const Duration(milliseconds: 100),
                                child: Row(
                                  children: nextSteps.map(_buildActionButton).toList(),
                                ),
                              ),
                            ] else ...[
                              AnimatedListItem(
                                index: 3,
                                delay: const Duration(milliseconds: 100),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: currentStatus == 'completed'
                                        ? AppTheme.secondaryColor.withValues(alpha: 0.08)
                                        : AppTheme.surfaceLowest,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: currentStatus == 'completed'
                                          ? AppTheme.secondaryColor.withValues(alpha: 0.2)
                                          : AppTheme.outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        currentStatus == 'completed'
                                            ? Icons.check_circle_rounded
                                            : Icons.info_outline_rounded,
                                        color: currentStatus == 'completed'
                                            ? AppTheme.secondaryColor
                                            : AppTheme.outline,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          currentStatus == 'completed'
                                              ? 'Trip completed. Great work!'
                                              : 'No further action required.',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: currentStatus == 'completed'
                                                ? AppTheme.secondaryColor
                                                : AppTheme.outline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
