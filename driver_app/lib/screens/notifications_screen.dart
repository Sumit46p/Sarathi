import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  String? _errorMsg;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final notifications = await ApiService.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
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
        _errorMsg = 'Failed to load notifications.';
      });
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'trip':
        return Icons.route_rounded;
      case 'issue':
        return Icons.report_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'trip':
        return AppTheme.primaryColor;
      case 'issue':
        return AppTheme.errorColor;
      case 'admin':
        return AppTheme.secondaryColor;
      default:
        return AppTheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
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
                                onPressed: _loadNotifications,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text('Retry', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _notifications.isEmpty
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
                                      child: const Icon(Icons.notifications_none_rounded, size: 48, color: AppTheme.primaryColor),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'No notifications',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'You will be notified here when dispatched or when admin sends alerts.',
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
                            itemCount: _notifications.length,
                            itemBuilder: (context, index) {
                              final notification = _notifications[index];
                              return AnimatedListItem(
                                index: index,
                                delay: const Duration(milliseconds: 60),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceLowest,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _typeColor(notification['type']).withValues(alpha: 0.2)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: _typeColor(notification['type']).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(_typeIcon(notification['type']), color: _typeColor(notification['type']), size: 20),
                                    ),
                                    title: Text(
                                      notification['title'] ?? 'Notification',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.onSurface,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text(
                                          notification['message'] ?? '',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: AppTheme.outline,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTimestamp(notification['timestamp']),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            color: AppTheme.outline.withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          _buildBottomNav(2),
        ],
      ),
    );
  }

  Widget _buildBottomNav(int activeIndex) {
    const items = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
      _NavItem(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Trips'),
      _NavItem(icon: Icons.notifications_none_rounded, activeIcon: Icons.notifications_active_rounded, label: 'Alerts'),
      _NavItem(icon: Icons.sentiment_satisfied_alt_outlined, activeIcon: Icons.sentiment_satisfied_alt_rounded, label: 'Me'),
    ];

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < items.length; i++) _buildNavItem(items[i], i, activeIndex),
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, int index, int activeIndex) {
    final isActive = activeIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (index == 2) {
          _loadNotifications();
        } else {
          Navigator.of(context).pop();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: isActive ? 40 : 0,
              height: 4,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (!isActive) const SizedBox(height: 8),
            AnimatedScale(
              scale: isActive ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.primaryColor : AppTheme.outline,
                letterSpacing: 0.3,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
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
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
