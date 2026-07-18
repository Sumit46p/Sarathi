import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/stat_card.dart';
import '../widgets/action_button.dart';
import 'trips_screen.dart';
import 'sos_screen.dart';
import 'camera_log_screen.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String _currentStatus = 'On Duty (Available)';

  final List<String> _statuses = [
    'On Duty (Available)',
    'On Duty (Busy)',
    'On Duty (Break)',
    'Off Duty',
  ];

  // ── Firebase helpers ──────────────────────────────────────────────────────
  Color _getStatusColor(String status) {
    if (status.contains('Available')) return AppTheme.secondaryColor;
    if (status.contains('Busy')) return AppTheme.errorColor;
    if (status.contains('Break')) return AppTheme.tertiaryColor;
    return AppTheme.outline;
  }

  // Humanized emoji representation of duty status (replaces plain icons).
  String _getStatusEmoji(String status) {
    if (status.contains('Available')) return '😊';
    if (status.contains('Busy')) return '🚗';
    if (status.contains('Break')) return '☕';
    return '😴';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _currentStatus = newStatus);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .set({'status': newStatus}, SetOptions(merge: true));
    } catch (_) {}
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  void _navigateTo(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  // ── Logout flow ───────────────────────────────────────────────────────────
  void _handleMenuSelection(String value) {
    if (value == 'logout') {
      _confirmLogout();
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log out?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to log out of your account?',
          style: GoogleFonts.plusJakartaSans(color: AppTheme.outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: AppTheme.outline,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Logout',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.errorColor,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _performLogout();
    }
  }

  Future<void> _performLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final List<Widget> screens = [
      _buildHomeBody(uid),
      const TripsScreen(),
      _buildAlertsBody(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: screens[_selectedIndex],
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    const items = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
      _NavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Trips'),
      _NavItem(
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_active_rounded,
          label: 'Alerts'),
      _NavItem(
          icon: Icons.sentiment_satisfied_alt_outlined,
          activeIcon: Icons.sentiment_satisfied_alt_rounded,
          label: 'Me'),
    ];

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _buildNavItem(items[i], i),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index) {
    final isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isActive)
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              const SizedBox(height: 8),
            AnimatedScale(
              scale: isActive ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Home Body ─────────────────────────────────────────────────────────────
  Widget _buildHomeBody(String? uid) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildTopHeader(uid),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverviewCard(uid),
                const SizedBox(height: 24),
                _buildQuickActionsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Deep-blue header ──────────────────────────────────────────────────────
  Widget _buildTopHeader(String? uid) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: Container(
        width: double.infinity,
        color: AppTheme.primaryColor,
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 48),
        child: Column(
          children: [
            StreamBuilder<DocumentSnapshot>(
              stream: uid == null
                  ? null
                  : FirebaseFirestore.instance.collection('drivers').doc(uid).snapshots(),
              builder: (ctx, snap) {
                final data = (snap.hasData && snap.data!.exists)
                    ? snap.data!.data() as Map
                    : null;
                final imageUrl = data?['profileImageUrl'];
                final name = (data?['name'] as String?)?.trim();
                final firstName =
                    (name != null && name.isNotEmpty) ? name.split(' ').first : 'Driver';

                return Row(
                  children: [
                    // Avatar
                    GestureDetector(
                      onTap: () => setState(() => _selectedIndex = 3),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Colors.white.withValues(alpha: 0.3),
                            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                            child: imageUrl == null
                                ? const Icon(Icons.emoji_people_rounded,
                                    size: 28, color: Colors.white)
                                : null,
                          ),
                          Positioned(
                            bottom: 1,
                            right: 1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryFixed,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primaryColor, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Greeting
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(firstName),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _getSubGreeting(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _showStatusPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _getStatusEmoji(_currentStatus),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _currentStatus,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.expand_more_rounded,
                                      size: 14, color: Colors.white70),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Three-dot menu (logout, etc.)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      color: AppTheme.surfaceLowest,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: _handleMenuSelection,
                      itemBuilder: (ctx) => [
                        PopupMenuItem<String>(
                          value: 'logout',
                          child: Row(
                            children: [
                              const Icon(Icons.logout_rounded,
                                  size: 18, color: AppTheme.errorColor),
                              const SizedBox(width: 10),
                              Text(
                                'Logout',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.errorColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getGreeting(String name) {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning, $name! ☀️';
    if (hour < 17) return 'Good Afternoon, $name! 👋';
    return 'Good Evening, $name! 🌙';
  }

  String _getSubGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Let's make today a great one on the road.";
    if (hour < 17) return 'Hope your day is going smoothly!';
    return 'Almost done for today — drive safe!';
  }

  void _showStatusPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              "How are you feeling today?",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Let dispatch know your current status',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            ..._statuses.map((s) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _getStatusColor(s).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _getStatusEmoji(s),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  title: Text(s, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
                  trailing: s == _currentStatus
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppTheme.secondaryColor, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _updateStatus(s);
                  },
                )),
          ],
        ),
      ),
    );
  }

  // ── Today's Overview card ─────────────────────────────────────────────────
  Widget _buildOverviewCard(String? uid) {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.wb_sunny_rounded,
                          size: 16, color: AppTheme.primaryColor),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Today's Overview",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${DateTime.now().day} ${_monthName(DateTime.now().month)} ${DateTime.now().year}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.outline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_month_rounded, size: 14, color: AppTheme.outline),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Metric grid
            StreamBuilder<QuerySnapshot>(
              stream: uid == null
                  ? null
                  : FirebaseFirestore.instance
                      .collection('trips')
                      .where('driverId', isEqualTo: uid)
                      .snapshots(),
              builder: (ctx, snap) {
                final totalTrips = snap.hasData ? snap.data!.docs.length : 0;

                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.82,
                  children: [
                    StatCard(
                      title: 'Total Trips',
                      value: '$totalTrips',
                      subtitle: 'Trips Completed',
                      icon: Icons.local_taxi_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    StatCard(
                      title: 'Distance',
                      value: '—',
                      subtitle: 'Distance Covered',
                      icon: Icons.signpost_rounded,
                      color: AppTheme.secondaryColor,
                    ),
                    StatCard(
                      title: 'On Duty Time',
                      value: '—',
                      subtitle: 'Total On Duty',
                      icon: Icons.access_time_filled_rounded,
                      color: AppTheme.tertiaryColor,
                    ),
                    StatCard(
                      title: 'Efficiency',
                      value: '—',
                      subtitle: 'Avg Efficiency',
                      icon: Icons.emoji_events_rounded,
                      color: const Color(0xFF653E00),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flash_on_rounded, size: 16, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 10),
            Text(
              'Quick Actions',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ActionButton(
              label: 'Start\nDuty',
              icon: Icons.play_circle_fill_rounded,
              color: AppTheme.secondaryColor,
              onTap: () {
                _updateStatus('On Duty (Available)');
                setState(() => _selectedIndex = 1);
              },
            ),
            ActionButton(
              label: 'SOS\nHelp',
              icon: Icons.emergency_share_rounded,
              color: AppTheme.errorColor,
              onTap: () => _navigateTo(const SOSScreen()),
            ),
            ActionButton(
              label: 'Fuel\nEntry',
              icon: Icons.local_gas_station_rounded,
              color: AppTheme.primaryColor,
              onTap: () => _navigateTo(const CameraLogScreen(logType: LogType.fuel)),
            ),
            ActionButton(
              label: 'Report\nIssue',
              icon: Icons.build_circle_rounded,
              color: const Color(0xFF7C3AED),
              onTap: () => _navigateTo(const CameraLogScreen(logType: LogType.maintenance)),
            ),
            ActionButton(
              label: 'Inspect\nVehicle',
              icon: Icons.fact_check_rounded,
              color: AppTheme.tertiaryColor,
              onTap: () => _navigateTo(const CameraLogScreen(logType: LogType.maintenance)),
            ),
            ActionButton(
              label: 'Messages',
              icon: Icons.mark_chat_unread_rounded,
              color: const Color(0xFF0D9488),
              onTap: () {},
              
            ),
            // Extra messaging action — quick voice/call icon alongside chat.
            ActionButton(
              label: 'Call\nSupport',
              icon: Icons.call_rounded,
              color: const Color(0xFF16A34A),
              onTap: () {},
            ),
            ActionButton(
              label: 'View\nMap',
              icon: Icons.explore_rounded,
              color: const Color(0xFF2563EB),
              onTap: () => setState(() => _selectedIndex = 1),
            ),
            ActionButton(
              label: 'Trip\nHistory',
              icon: Icons.history_rounded,
              color: AppTheme.outline,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }

  // ── Alerts body ───────────────────────────────────────────────────────────
  Widget _buildAlertsBody() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Alerts',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('alerts')
            .orderBy('timestamp', descending: true)
            .limit(30)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
          }
          final alerts = snap.data?.docs ?? [];
          if (alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.celebration_rounded,
                        size: 56, color: AppTheme.secondaryColor),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "You're all caught up!",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No alerts right now — enjoy the calm.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppTheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: alerts.length,
            itemBuilder: (ctx, i) {
              final data = alerts[i].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.tertiaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.notifications_active_rounded,
                          color: AppTheme.tertiaryColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Alert',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data['message'] ?? '',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.outline, size: 20),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month];
  }
}

// ── Helper record for nav items ────────────────────────────────────────────
class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}