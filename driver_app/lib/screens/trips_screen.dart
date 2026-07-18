import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});
  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Completed', 'Ongoing'];

  IconData _filterIcon(String f) {
    switch (f) {
      case 'Completed':
        return Icons.check_circle_rounded;
      case 'Ongoing':
        return Icons.directions_car_filled_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  IconData _statusIcon(String status) {
    if (status == 'In Progress') return Icons.directions_car_filled_rounded;
    if (status == 'Completed') return Icons.check_circle_rounded;
    return Icons.schedule_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('trips')
                  .where('driverId', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
                }
                final allTrips = snapshot.data?.docs ?? [];
                final filtered = _filterTrips(allTrips);
                if (filtered.isEmpty) return _buildEmpty();
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryRow(),
                      const SizedBox(height: 20),
                      _buildFilterRow(),
                      const SizedBox(height: 16),
                      ...filtered.map(_buildTripCard),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trips',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('Check your rides',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_active_rounded, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Trips',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text('A quick look at the road behind you',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _statTile(
                    icon: Icons.signpost_rounded,
                    label: 'Total Distance',
                    value: '1,248',
                    unit: 'km',
                    color: AppTheme.primaryColor)),
            const SizedBox(width: 12),
            Expanded(
                child: _statTile(
                    icon: Icons.access_time_filled_rounded,
                    label: 'Hours Driven',
                    value: '42.5',
                    unit: 'hrs',
                    color: AppTheme.secondaryColor)),
          ]),
        ],
      ),
    );
  }

  Widget _statTile(
      {required IconData icon,
      required String label,
      required String value,
      required String unit,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceVariant.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.outline, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: value, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
              TextSpan(text: ' $unit', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((f) {
          final isActive = _activeFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _activeFilter = f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.primaryColor : AppTheme.surfaceLowest,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: isActive ? AppTheme.primaryColor : AppTheme.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: isActive
                      ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_filterIcon(f), size: 14, color: isActive ? Colors.white : AppTheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(f,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isActive ? Colors.white : AppTheme.onSurfaceVariant,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTripCard(QueryDocumentSnapshot doc) {
    final trip = doc.data() as Map<String, dynamic>;
    final status = trip['status'] ?? 'Pending';
    final pickup = trip['pickup'] ?? 'Unknown';
    final dropoff = trip['dropoff'] ?? 'Unknown';
    final scheduledAt = trip['scheduledAt'] as Timestamp?;
    final isOngoing = status == 'In Progress';
    final Color statusColor = isOngoing ? AppTheme.primaryColor : (status == 'Completed' ? AppTheme.secondaryColor : AppTheme.outline);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: isOngoing ? AppTheme.primaryColor : AppTheme.surfaceVariant.withValues(alpha: 0.5), width: isOngoing ? 4 : 1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _statusBadge(status, statusColor, isOngoing),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.confirmation_number_rounded, size: 14, color: AppTheme.outline),
                        const SizedBox(width: 4),
                        Text('Trip #${doc.id.substring(0, 6).toUpperCase()}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      ],
                    ),
                  ],
                ),
                if (scheduledAt != null)
                  Row(
                    children: [
                      const Icon(Icons.event_rounded, size: 13, color: AppTheme.outline),
                      const SizedBox(width: 4),
                      Text(_formatDate(scheduledAt.toDate()), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.outline)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _dot(AppTheme.primaryColor, true),
                    Container(width: 2, height: 28, color: AppTheme.surfaceContainer),
                    _dot(status == 'Completed' ? AppTheme.secondaryColor : AppTheme.outline, status == 'Completed'),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pick up', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.outline)),
                      Text(pickup, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                      const SizedBox(height: 14),
                      Text('Destination', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.outline)),
                      Text(dropoff, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: AppTheme.surfaceVariant.withValues(alpha: 0.4), height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.signpost_rounded, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 4),
                Text('${trip['distance'] ?? '—'} km', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time_filled_rounded, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 4),
                Text(trip['duration'] ?? '—', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                const Spacer(),
                if (status == 'Completed')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Details',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.primaryColor),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, bool filled) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : AppTheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Center(child: Container(width: 7, height: 7, decoration: BoxDecoration(color: filled ? color : AppTheme.outline, shape: BoxShape.circle))),
    );
  }

  Widget _statusBadge(String status, Color color, bool isOngoing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 11, color: color),
          const SizedBox(width: 5),
          Text(status == 'In Progress' ? 'Ongoing' : status,
              style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.06), shape: BoxShape.circle),
            child: const Icon(Icons.map_rounded, size: 44, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 20),
          Text('No trips yet', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
          const SizedBox(height: 6),
          Text('Your next ride will show up here as soon\nas it\'s assigned.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.outline, height: 1.4)),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterTrips(List<QueryDocumentSnapshot> trips) {
    if (_activeFilter == 'All') return trips;
    if (_activeFilter == 'Completed') return trips.where((d) => (d.data() as Map)['status'] == 'Completed').toList();
    return trips.where((d) => (d.data() as Map)['status'] == 'In Progress').toList();
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month) return 'Today, ${_time(dt)}';
    return '${dt.day} ${_month(dt.month)}, ${_time(dt)}';
  }

  String _time(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  String _month(int m) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[m];
  }
}