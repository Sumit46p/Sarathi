import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/truck_loader.dart';

/// Active-trip tracking screen for drivers.
///
/// Mirrors a real fleet-management dispatch view: a live map with the unit
/// and destination, a trip progress bar with ETA, a status stepper and the
/// valid next actions for the current lifecycle stage.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _dispatch;
  bool _loading = true;
  String? _errorMsg;
  bool _transitioning = false;
  Timer? _pollTimer;
  final MapController _mapController = MapController();
  bool _mapReady = false;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
  
  // Pickup confirmation state
  bool _showPickupConfirmDialog = false;
  bool _confirmingPickup = false;

  static const Map<String, List<String>> _validTransitions = {
    'assigned': ['accepted', 'cancelled'],
    'accepted': ['en_route', 'cancelled'],
    'en_route': ['arrived', 'cancelled', 'AT_PICKUP'],
    'arrived': ['completed', 'cancelled'],
    'AT_PICKUP': ['completed', 'cancelled'],
  };

  static const Map<String, String> _statusLabels = {
    'assigned': 'Assigned',
    'accepted': 'Accepted',
    'en_route': 'En Route',
    'arrived': 'Arrived',
    'completed': 'Completed',
    'cancelled': 'Cancelled',
    'AT_PICKUP': 'At Pickup',
  };

  // Stepper order used to render the lifecycle timeline.
  static const List<String> _stepOrder = [
    'assigned',
    'accepted',
    'en_route',
    'AT_PICKUP',
    'arrived',
    'completed',
  ];

  static const Map<String, IconData> _stepIcons = {
    'assigned': Icons.assignment_outlined,
    'accepted': Icons.check_circle_outline,
    'en_route': Icons.directions_car_outlined,
    'arrived': Icons.place_outlined,
    'completed': Icons.flag_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadDispatch();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _loadDispatch(showLoading: false));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulse.dispose();
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
      _fitMap();
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

  LatLng? _vehicleLocation() {
    final loc = _dispatch?['assigned_vehicle_location'];
    if (loc is Map) {
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return null;
  }

  LatLng? _requestLocation() {
    final lat = (_dispatch?['request_lat'] as num?)?.toDouble();
    final lng = (_dispatch?['request_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  LatLng? _destinationLocation() {
    final lat = (_dispatch?['dest_lat'] as num?)?.toDouble();
    final lng = (_dispatch?['dest_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  String _pickupName() => _dispatch?['location_name']?.toString() ?? 'Pickup';
  String _destName() => _dispatch?['destination_name']?.toString() ?? 'Destination';

  void _fitMap() {
    if (!_mapReady) return;
    final points = <LatLng>[
      ..._decodeGeometry(_dispatch?['geometry']),
      if (_vehicleLocation() case final v?) v,
      if (_requestLocation() case final r?) r,
      if (_destinationLocation() case final d?) d,
    ];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 14);
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(48, 48, 48, 120),
        ),
      );
    } catch (_) {
      _mapController.move(points.first, 14);
    }
Future<void> _transition(String next) async {
      // Extract location from dispatch data for GPS validation
      double? pickupLat, pickupLng, destinationLat, destinationLng;
      
      final vehicleLoc = _dispatch?['assigned_vehicle_location'];
      if (vehicleLoc is Map) {
        pickupLat = (vehicleLoc['lat'] as num?)?.toDouble();
        pickupLng = (vehicleLoc['lng'] as num?)?.toDouble();
      }
      
      final destLoc = _dispatch?['destination_location'];
      if (destLoc is Map) {
        destinationLat = (destLoc['lat'] as num?)?.toDouble();
        destinationLng = (destLoc['lng'] as num?)?.toDouble();
      }
      
      setState(() => _transitioning = true);
      try {
        final result = await ApiService.transitionDispatch(
          status: next,
          pickupLat: pickupLat,
          pickupLng: pickupLng,
          destinationLat: (next == 'completed' || next == 'arrived') ? destinationLat : null,
          destinationLng: (next == 'completed' || next == 'arrived') ? destinationLng : null,
        );
        if (!mounted) return;
        setState(() => _transitioning = false);
        
        // Show GPS warnings if returned from server
        if (result is Map && result['gps_warnings'] != null) {
          final warnings = List<String>.from(result['gps_warnings'] as List);
          final gpsErrors = warnings.join('\n\n');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$gpsErrors\n\n⚠️ Admin override successful (emergency only).'),
              backgroundColor: AppTheme.warningColor,
              duration: const Duration(seconds: 8),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        
        setState(() => _dispatch = (result is Map && result['admin_override'] == true) ? _dispatch! : result);
        _fitMap();
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _transitioning = false);
        
        // Map API error messages to user-friendly GPS-specific messages
        String errorMessage = e.message;
        
        if (e.message.contains('GPS signal unavailable')) {
          errorMessage = '📍 Location Required\n\nPlease enable location services and wait for GPS lock before proceeding.';
        } else if (e.message.contains('GPS stale') || e.message.contains('GPS outdated')) {
          errorMessage = '📍 Location Signal Outdated\n\nPlease ensure location services are enabled and try again in a moment.';
        } else if (e.message.contains('Movement required') || e.message.contains('No movement')) {
          errorMessage = '🚗 Movement Required\n\nYou must start moving from the pickup. Please drive away before marking "En Route".';
        } else if (e.message.contains('Too far from destination') || e.message.contains('Not at destination')) {
          errorMessage = '📍 Not at Destination\n\nYou must be within 500m of the destination. Please continue driving.';
        } else if (e.message.contains('Admin Override')) {
          errorMessage = '⚠️ Admin Override\n\nThis transition was approved by an administrator (emergency use only).';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _transitioning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update trip: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _transition(String next) async {
    setState(() => _transitioning = true);
    try {
      final result = await ApiService.transitionDispatch(status: next);
      if (!mounted) return;
      setState(() => _transitioning = false);
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update trip'),
              backgroundColor: AppTheme.errorColor),
        );
      } else {
        setState(() => _dispatch = result);
        _fitMap();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _transitioning = false);
      
      // Show detailed GPS validation error messages to the driver
      String errorMessage = e.message;
      
      // Extract detail field if available for more context
      if (e.message.contains('GPS signal required')) {
        errorMessage = '📍 Location Required\n\nPlease enable location services and wait for GPS lock before proceeding.';
      } else if (e.message.contains('GPS signal outdated')) {
        errorMessage = '📍 Location Signal Outdated\n\nPlease ensure location services are enabled and try again in a moment.';
      } else if (e.message.contains('Movement required')) {
        errorMessage = '🚗 Movement Required\n\nYou must start moving before marking "En Route". Please drive away from the pickup location.';
      } else if (e.message.contains('Too far from destination')) {
        errorMessage = '📍 Not at Destination\n\nYou must be near the destination to mark this status. Please continue driving.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _transitioning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update trip: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
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
    final route = _decodeGeometry(_dispatch?['geometry']);
    final vehicle = _vehicleLocation();
    final request = _requestLocation();
    final dest = _destinationLocation();

    LatLng center;
    if (vehicle != null) {
      center = vehicle;
    } else if (route.isNotEmpty) {
      center = route.first;
    } else if (request != null) {
      center = request;
    } else {
      center = const LatLng(27.7, 85.3);
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            onMapReady: () {
              _mapReady = true;
              _fitMap();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.company.sarthi',
            ),
            if (route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 6,
                    color: AppTheme.primaryColor.withValues(alpha: 0.35),
                  ),
                  Polyline(
                    points: route,
                    strokeWidth: 3,
                    color: AppTheme.primaryColor,
                  ),
                ],
              ),
            if (vehicle != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: vehicle,
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    child: _PulsingVehicleMarker(pulse: _pulse),
                  ),
                ],
              ),
            // Pickup marker with label
            if (request != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: request,
                    width: 100,
                    height: 64,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Text(
                            _pickupName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Icon(Icons.location_on, color: AppTheme.errorColor, size: 32),
                      ],
                    ),
                  ),
                ],
              ),
            // Destination marker with label
            if (dest != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: dest,
                    width: 110,
                    height: 64,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Text(
                            _destName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Icon(Icons.flag_rounded, color: AppTheme.primaryColor, size: 32),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        // Recenter / zoom controls
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(
            children: [
              _MapControlButton(
                icon: Icons.my_location,
                tooltip: 'Center on my vehicle',
                onTap: () {
                  HapticFeedback.lightImpact();
                  final v = _vehicleLocation();
                  if (v != null) {
                    _mapController.move(v, 15);
                  } else {
                    _fitMap();
                  }
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (!_mapReady) return;
                  final zoom = (_mapController.camera.zoom + 1).clamp(3.0, 18.0).toDouble();
                  _mapController.move(_mapController.camera.center, zoom);
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (!_mapReady) return;
                  final zoom = (_mapController.camera.zoom - 1).clamp(3.0, 18.0).toDouble();
                  _mapController.move(_mapController.camera.center, zoom);
                },
              ),
            ],
          ),
        ),
        // Legend chip
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping_outlined, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text('My Vehicle', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                const SizedBox(width: 10),
                Icon(Icons.location_on, size: 14, color: AppTheme.errorColor),
                const SizedBox(width: 4),
                Text('Pickup', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                const SizedBox(width: 10),
                Icon(Icons.flag_rounded, size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text('Destination', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
              ],
            ),
          ),
        ),
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

  /// Horizontal lifecycle stepper showing Assigned → … → Completed.
  Widget _buildStatusStepper(String? currentStatus) {
    final currentIdx = _stepOrder.indexOf(currentStatus ?? '');
    return Row(
      children: List.generate(_stepOrder.length, (i) {
        final step = _stepOrder[i];
        final isDone = currentIdx >= 0 && i < currentIdx;
        final isActive = currentIdx == i;
        final color = isDone || isActive
            ? AppTheme.primaryColor
            : AppTheme.outline;
        return Expanded(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primaryColor
                      : isDone
                          ? AppTheme.primaryColor.withValues(alpha: 0.15)
                          : AppTheme.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color,
                    width: isActive ? 2 : 1.5,
                  ),
                ),
                child: isActive
                    ? FadeTransition(
                        opacity: _pulse,
                        child: Icon(
                          _stepIcons[step],
                          size: 18,
                          color: AppTheme.onPrimary,
                        ),
                      )
                    : Icon(
                        isDone ? Icons.check_rounded : _stepIcons[step],
                        size: 18,
                        color: isDone ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                _statusLabels[step]!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppTheme.primaryColor
                      : isDone
                          ? AppTheme.onSurface
                          : AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLiveTrackingCard() {
    final progress = (_dispatch?['progress_percent'] as num?)?.toDouble();
    final eta = (_dispatch?['eta_min'] as num?)?.toDouble();
    final remaining = (_dispatch?['remaining_distance_km'] as num?)?.toDouble();
    final totalKm = (_dispatch?['distance_km'] as num?)?.toDouble();

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
                'TRIP PROGRESS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.successLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress != null && progress >= 0
                  ? (progress / 100).clamp(0.0, 1.0)
                  : null,
              minHeight: 8,
              backgroundColor: AppTheme.surfaceVariant,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCell(
                  icon: Icons.schedule,
                  value: eta != null
                      ? '${eta.round()} min'
                      : '—',
                  label: 'ETA',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.route,
                  value: remaining != null
                      ? '${remaining.toStringAsFixed(1)} km'
                      : '—',
                  label: 'Remaining',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.straighten,
                  value: totalKm != null
                      ? '${totalKm.toStringAsFixed(1)} km'
                      : '—',
                  label: 'Distance',
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.trending_up,
                  value: progress != null
                      ? '${progress.round()}%'
                      : '—',
                  label: 'Done',
                ),
              ),
            ],
          ),
        ],
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
    final isCompleted = currentStatus == 'completed';
    final isCancelled = currentStatus == 'cancelled';

    final isEmergency = _dispatch?['request_type'] == 'EMERGENCY' ||
        _dispatch?['operation_type'] == 'EMERGENCY_REPLACEMENT';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _loading
            ? const TruckLoaderCenter()
            : _errorMsg != null && _dispatch == null
                ? _buildError()
                : _dispatch == null
                    ? _buildEmpty()
                    : Column(
                        children: [
                          // Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isEmergency ? AppTheme.errorColor : AppTheme.primaryColor).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isEmergency ? Icons.warning_amber_rounded : Icons.map_outlined,
                                    color: isEmergency ? AppTheme.errorColor : AppTheme.primaryColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isEmergency ? '🚨 Emergency Dispatch' : 'Active Trip',
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: isEmergency ? AppTheme.errorColor : AppTheme.onSurface,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (isCompleted
                                            ? AppTheme.successLight
                                            : isCancelled
                                                ? AppTheme.errorLight
                                                : (isEmergency ? AppTheme.errorColor : AppTheme.primaryColor)
                                                    .withOpacity(0.1)),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isCompleted
                                              ? AppTheme.successColor
                                              : isCancelled
                                                  ? AppTheme.errorColor
                                                  : (isEmergency ? AppTheme.errorColor : AppTheme.primaryColor),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _statusLabels[currentStatus] ?? currentStatus ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isCompleted
                                              ? AppTheme.successColor
                                              : isCancelled
                                                  ? AppTheme.errorColor
                                                  : (isEmergency ? AppTheme.errorColor : AppTheme.primaryColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (isEmergency)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.errorColor, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.emergency_rounded, color: AppTheme.errorColor, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'CRITICAL EMERGENCY RESPONSE',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.errorColor,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          Text(
                                            _dispatch?['cargo_description'] ?? _dispatch?['location_name'] ?? 'Respond immediately to emergency site',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
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

                          // Trip details
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Status stepper
                                  _buildStatusStepper(currentStatus),
                                  const SizedBox(height: 20),

                                  // Live tracking card
                                  _buildLiveTrackingCard(),
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
                                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
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
                                        if (_vehicleLocation() != null)
                                          const Icon(
                                            Icons.gps_fixed,
                                            color: AppTheme.successColor,
                                            size: 18,
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
                                        color: isCompleted
                                            ? AppTheme.successLight
                                            : AppTheme.surfaceVariant,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isCompleted
                                                ? Icons.check_circle_rounded
                                                : Icons.info_outline_rounded,
                                            color: isCompleted
                                                ? AppTheme.successColor
                                                : AppTheme.onSurfaceVariant,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              isCompleted
                                                  ? 'Trip completed. Great work!'
                                                  : 'No further action required.',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: isCompleted
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

/// Pulsing vehicle marker with a soft halo ring around the unit icon.
class _PulsingVehicleMarker extends StatelessWidget {
  final Animation<double> pulse;
  const _PulsingVehicleMarker({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final t = pulse.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: (0.25 * (1 - t))),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: (0.6 * (1 - t))),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Floating map control button (recenter / zoom).
class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: AppTheme.onSurface),
          ),
        ),
      ),
    );
  }
}

/// Small labelled stat cell for the live tracking card.
class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppTheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
