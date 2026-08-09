import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<dynamic> _trips = [];
  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadTripHistory();
  }

  Future<void> _loadTripHistory() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final trips = await ApiService.getTripHistory();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Failed to load trip history.';
      });
    }
  }

  String _formatTimestamp(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final date = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$date $time';
    } catch (_) {
      return iso;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppTheme.secondaryColor;
      case 'cancelled':
        return AppTheme.errorColor;
      case 'rejected':
        return AppTheme.errorColor;
      default:
        return AppTheme.outline;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'rejected':
        return Icons.thumb_down_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Widget _buildTripCard(Map<String, dynamic> trip) {
    final status = trip['status'] ?? 'unknown';
    final vehicleName = trip['vehicle_name'] ?? trip['assigned_vehicle_name'] ?? 'Unknown Vehicle';
    final plate = trip['number_plate'] ?? '—';
    final assignedTime = _formatTimestamp(trip['assigned_at']);
    final completedTime = _formatTimestamp(trip['completed_at'] ?? trip['cancelled_at'] ?? trip['rejected_at']);
    final tripDuration = trip['trip_duration_seconds'];

    String durationText = '—';
    if (tripDuration != null) {
      final mins = (tripDuration / 60).floor();
      final secs = (tripDuration % 60).floor();
      durationText = mins > 0 ? '$mins min $secs sec' : '$secs sec';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon(status), color: _statusColor(status), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      status.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(status),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                if (trip['distance_km'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(trip['distance_km'] as num).toStringAsFixed(1)} km',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.directions_car_rounded, size: 16, color: AppTheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    vehicleName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.pin_drop_rounded, size: 16, color: AppTheme.outline),
                const SizedBox(width: 8),
                  Text(
                    plate,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assigned',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.outline,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        assignedTime,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: AppTheme.outlineVariant,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status == 'completed' ? 'Completed' : (status == 'cancelled' ? 'Cancelled' : 'Rejected'),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.outline,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          completedTime,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (durationText != '—') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.timer_rounded, size: 14, color: AppTheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Trip duration: $durationText',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.outline,
                    ),
                  ),
                ],
              ),
            ],
            if (((trip['point_count'] as num?) ?? 0) > 0) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openPlayback(trip),
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                  label: Text(
                    'View Route Playback',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openPlayback(Map<String, dynamic> trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TripPlaybackSheet(
        dispatchId: trip['id'] as int,
        vehicleName: (trip['vehicle_name'] as String?) ?? 'Unknown Vehicle',
        numberPlate: (trip['number_plate'] as String?) ?? '—',
        requestLat: (trip['request_lat'] as num?)?.toDouble(),
        requestLng: (trip['request_lng'] as num?)?.toDouble(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Trip History', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : _errorMsg != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.errorColor),
                              const SizedBox(height: 16),
                              Text(_errorMsg!, textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadTripHistory,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _trips.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
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
                                      child: const Icon(Icons.history_rounded, size: 48, color: AppTheme.primaryColor),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'No trips yet',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Completed and rejected trips will appear here.',
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
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: _trips.length,
                            itemBuilder: (context, index) {
                              return AnimatedListItem(
                                index: index,
                                delay: const Duration(milliseconds: 60),
                                child: _buildTripCard(_trips[index]),
                              );
                            },
                           ),
          ),
        ],
      ),
    );
  }
}

class _TripPlaybackSheet extends StatefulWidget {
  const _TripPlaybackSheet({
    required this.dispatchId,
    required this.vehicleName,
    required this.numberPlate,
    this.requestLat,
    this.requestLng,
  });

  final int dispatchId;
  final String vehicleName;
  final String numberPlate;
  final double? requestLat;
  final double? requestLng;

  @override
  State<_TripPlaybackSheet> createState() => _TripPlaybackSheetState();
}

class _TripPlaybackSheetState extends State<_TripPlaybackSheet>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _errorMsg;
  List<LatLng> _points = [];
  List<double> _speeds = [];
  List<int> _segmentMs = [];
  int _totalMs = 0;
  double _elapsedMs = 0;
  double _speed = 1;
  bool _playing = false;
  Timer? _timer;
  final MapController _mapController = MapController();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final data = await ApiService.getTripPlayback(widget.dispatchId);
      if (!mounted) return;
      final rawPoints = data['points'] as List<dynamic>? ?? [];
      final points = <LatLng>[];
      final speeds = <double>[];
      for (final p in rawPoints) {
        final lat = (p['lat'] as num?)?.toDouble();
        final lng = (p['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        points.add(LatLng(lat, lng));
        speeds.add((p['speed_kmh'] as num?)?.toDouble() ?? 0);
      }
      if (points.isEmpty) {
        setState(() {
          _loading = false;
          _errorMsg = 'No GPS points recorded for this trip.';
        });
        return;
      }
      final segmentMs = <int>[];
      DateTime? prev;
      for (final p in rawPoints) {
        final t = DateTime.tryParse((p['recorded_at'] as String?) ?? '');
        if (prev != null && t != null) {
          final d = t.difference(prev).inMilliseconds;
          segmentMs.add(d > 0 && d < 3600000 ? d : 4000);
        }
        prev = t;
      }
      while (segmentMs.length < points.length - 1) {
        segmentMs.add(4000);
      }
      int total = 0;
      for (final d in segmentMs) {
        total += d;
      }
      setState(() {
        _points = points;
        _speeds = speeds;
        _segmentMs = segmentMs;
        _totalMs = total > 0 ? total : 4000;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitCamera();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Failed to load route: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'An unexpected error occurred.';
      });
    }
  }

  void _fitCamera() {
    final all = <LatLng>[..._points];
    if (widget.requestLat != null && widget.requestLng != null) {
      all.add(LatLng(widget.requestLat!, widget.requestLng!));
    }
    if (all.isEmpty) return;
    if (all.length == 1) {
      _mapController.move(all.first, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(all),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  void _togglePlay() {
    if (!_playing && _elapsedMs >= _totalMs) {
      _elapsedMs = 0;
    }
    setState(() => _playing = !_playing);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    } else {
      _timer?.cancel();
    }
  }

  void _tick() {
    setState(() {
      _elapsedMs += 200 * _speed;
      if (_elapsedMs >= _totalMs) {
        _elapsedMs = _totalMs.toDouble();
        _playing = false;
        _timer?.cancel();
      }
    });
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _elapsedMs = 0;
      _playing = true;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  int _indexForMs(double ms) {
    int acc = 0;
    for (int i = 0; i < _segmentMs.length; i++) {
      acc += _segmentMs[i];
      if (ms < acc) return i;
    }
    return _points.length - 1;
  }

  LatLng _markerPosition() {
    if (_points.length < 2) return _points.isEmpty ? const LatLng(0, 0) : _points.first;
    int acc = 0;
    for (int i = 0; i < _segmentMs.length; i++) {
      final end = acc + _segmentMs[i];
      if (_elapsedMs < end) {
        final seg = _segmentMs[i];
        final f = seg > 0 ? (_elapsedMs - acc) / seg : 0.0;
        return LatLng(
          _points[i].latitude + (_points[i + 1].latitude - _points[i].latitude) * f,
          _points[i].longitude + (_points[i + 1].longitude - _points[i].longitude) * f,
        );
      }
      acc = end;
    }
    return _points.last;
  }

  double _currentSpeed() {
    if (_points.isEmpty) return 0;
    final idx = _indexForMs(_elapsedMs).clamp(0, _speeds.length - 1).toInt();
    return _speeds[idx];
  }

  String _fmtMs(double ms) {
    final s = (ms / 1000).floor();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _buildMap() {
    final traveled = _points.length > 1
        ? _points.sublist(0, _indexForMs(_elapsedMs) + 1)
        : List<LatLng>.of(_points);
    final markerPos = _markerPosition();

    final markers = <Marker>[];
    if (widget.requestLat != null && widget.requestLng != null) {
      markers.add(
        Marker(
          point: LatLng(widget.requestLat!, widget.requestLng!),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: AppTheme.errorColor, size: 36),
        ),
      );
    }
    markers.add(
      Marker(
        point: markerPos,
        width: 42,
        height: 42,
        child: ScaleTransition(
          scale: Tween(begin: 0.8, end: 1.2).animate(CurvedAnimation(
            parent: _pulse,
            curve: Curves.easeInOut,
          )),
          child: const Icon(Icons.navigation_rounded, color: AppTheme.primaryColor, size: 40),
        ),
      ),
    );

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _points.isNotEmpty ? _points.first : const LatLng(27.7, 85.3),
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.company.sarthi',
        ),
        if (_points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _points,
                strokeWidth: 6,
                color: AppTheme.outlineVariant,
              ),
              if (traveled.length > 1)
                Polyline(
                  points: traveled,
                  strokeWidth: 6,
                  color: AppTheme.secondaryColor,
                ),
            ],
          ),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      child: SizedBox(
        height: height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route Playback',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.vehicleName} · ${widget.numberPlate}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppTheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppTheme.outline),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                  : _errorMsg != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.route_rounded, size: 48, color: AppTheme.errorColor),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMsg!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(child: ClipRect(child: _buildMap())),
                            Container(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                              decoration: const BoxDecoration(
                                color: AppTheme.surfaceLowest,
                                border: Border(top: BorderSide(color: AppTheme.outlineVariant)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Slider(
                                    value: _elapsedMs.clamp(0, _totalMs.toDouble()).toDouble(),
                                    max: _totalMs.toDouble(),
                                    activeColor: AppTheme.primaryColor,
                                    inactiveColor: AppTheme.outlineVariant,
                                    onChanged: (v) {
                                      setState(() => _elapsedMs = v);
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _fmtMs(_elapsedMs),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: AppTheme.outline,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      Text(
                                        '${_currentSpeed().toStringAsFixed(0)} km/h',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                      Text(
                                        _fmtMs(_totalMs.toDouble()),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: AppTheme.outline,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        onPressed: _restart,
                                        icon: const Icon(Icons.replay_rounded),
                                        color: AppTheme.primaryColor,
                                        tooltip: 'Restart',
                                      ),
                                      const SizedBox(width: 16),
                                      IconButton.filled(
                                        onPressed: _togglePlay,
                                        icon: Icon(
                                          _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        ),
                                        iconSize: 30,
                                        style: IconButton.styleFrom(
                                          backgroundColor: AppTheme.primaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.all(14),
                                        ),
                                        tooltip: _playing ? 'Pause' : 'Play',
                                      ),
                                      const SizedBox(width: 16),
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            _speed = _speed == 1 ? 2 : (_speed == 2 ? 4 : 1);
                                          });
                                        },
                                        child: Text(
                                          '${_speed}x',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

