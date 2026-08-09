import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';

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

  // Stepper order used to render the lifecycle timeline.
  static const List<String> _stepOrder = [
    'assigned',
    'accepted',
    'en_route',
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

  void _fitMap() {
    if (!_mapReady) return;
    final points = <LatLng>[
      ..._decodeGeometry(_dispatch?['geometry']),
      if (_vehicleLocation() case final v?) v,
      if (_requestLocation() case final r?) r,
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
          padding: const EdgeInsets.fromLTRB(48, 48, 48, 48),
        ),
      );
    } catch (_) {
      _mapController.move(points.first, 14);
    }
  }

  Future<void> _transition(String next) async {
    setState(() => _transitioning = true);
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
            if (request != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: request,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on,
                        color: AppTheme.errorColor, size: 36),
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
        if (request != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  Icon(Icons.place,
                      size: 14, color: AppTheme.errorColor),
                  const SizedBox(width: 4),
                  Text(
                    'Scene',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.local_shipping_outlined,
                      size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    'My unit',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
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
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.map_outlined,
                                      color: AppTheme.primaryColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Active Trip',
                                    style: GoogleFonts.inter(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.onSurface,
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
                                                : AppTheme.primaryColor
                                                    .withValues(alpha: 0.1)),
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
                                                  : AppTheme.primaryColor,
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
                                                  : AppTheme.primaryColor,
                                        ),
                                      ),
                                    ],
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
