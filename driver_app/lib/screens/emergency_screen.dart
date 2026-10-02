import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/truck_loader.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  bool _isLoading = true;
  List<dynamic> _emergencies = [];
  String? _error;

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _selectedEmergencyType;
  bool _isSubmitting = false;
  Position? _currentPosition;
  bool _isLoadingLocation = false;
  File? _selectedImage;

  final List<Map<String, String>> _emergencyTypes = [
    {'value': 'medical', 'label': 'Medical Emergency', 'icon': '🏥'},
    {'value': 'accident', 'label': 'Accident', 'icon': '🚨'},
    {'value': 'breakdown', 'label': 'Vehicle Breakdown', 'icon': '🔧'},
    {'value': 'other', 'label': 'Other Emergency', 'icon': '❓'},
  ];

  @override
  void initState() {
    super.initState();
    _loadEmergencies();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadEmergencies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final list = await ApiService.getEmergencyRequests();
      if (mounted) {
        setState(() {
          _emergencies = list;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _emergencies = [];
          _isLoading = false;
          _error = 'Could not load emergency SOS history. Please try again.';
        });
      }
    }
  }

  Future<void> _getCurrentLocation(StateSetter setSheetState) async {
    setSheetState(() => _isLoadingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setSheetState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setSheetState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setSheetState(() => _isLoadingLocation = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setSheetState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
    } catch (e) {
      setSheetState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _pickImage(ImageSource source, StateSetter setSheetState) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        setSheetState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photo', style: GoogleFonts.inter())),
        );
      }
    }
  }

  Future<void> _submitEmergency(BuildContext sheetContext, StateSetter setSheetState) async {
    if (_selectedEmergencyType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select an emergency type', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    HapticFeedback.heavyImpact();
    setSheetState(() => _isSubmitting = true);

    Map<String, double>? location;
    if (_currentPosition != null) {
      location = {
        'lat': _currentPosition!.latitude,
        'lng': _currentPosition!.longitude,
      };
    }

    final success = await ApiService.createEmergencyRequest(
      emergencyType: _selectedEmergencyType!,
      description: _descriptionController.text.trim(),
      location: location,
      imagePath: _selectedImage?.path,
    );

    if (!mounted) return;
    setSheetState(() => _isSubmitting = false);

    if (success) {
      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      _descriptionController.clear();
      _selectedImage = null;
      _selectedEmergencyType = null;
      _currentPosition = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency SOS sent! Admin has been notified immediately.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      _loadEmergencies();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send emergency SOS. Please try again.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showAddEmergencySheet() {
    _descriptionController.clear();
    _selectedEmergencyType = null;
    _selectedImage = null;
    _currentPosition = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Initialize location fetch once when opened
          if (_currentPosition == null && !_isLoadingLocation) {
            _getCurrentLocation(setSheetState);
          }

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.emergency_rounded, color: AppTheme.errorColor, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Send Emergency SOS',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Emergency Type *',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),

                    ..._emergencyTypes.map((type) {
                      final isSelected = _selectedEmergencyType == type['value'];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setSheetState(() {
                            _selectedEmergencyType = type['value'];
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.errorColor.withOpacity(0.08)
                                : AppTheme.surfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.errorColor : AppTheme.outlineVariant,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(type['icon']!, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  type['label']!,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? AppTheme.errorColor : AppTheme.onSurface,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: AppTheme.errorColor, size: 20),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    const SizedBox(height: 16),

                    // Description
                    Text(
                      'Situation Details',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Briefly describe your situation, casualties, or hazards...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
                        filled: true,
                        fillColor: AppTheme.surfaceVariant.withOpacity(0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5),
                        ),
                      ),
                      style: GoogleFonts.inter(color: AppTheme.onSurface),
                    ),

                    const SizedBox(height: 16),

                    // Location Card
                    Text(
                      'Location (GPS)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.outlineVariant),
                      ),
                      child: _isLoadingLocation
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.errorColor),
                                ),
                                const SizedBox(width: 10),
                                Text('Fetching current GPS coordinates...', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                              ],
                            )
                          : _currentPosition != null
                              ? Row(
                                  children: [
                                    const Icon(Icons.location_on, color: AppTheme.errorColor, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Lat: ${_currentPosition!.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(5)}',
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                                      ),
                                    ),
                                    const Icon(Icons.check_circle, color: AppTheme.successColor, size: 18),
                                  ],
                                )
                              : Row(
                                  children: [
                                    const Icon(Icons.location_off_outlined, color: AppTheme.warningColor, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('GPS unavailable', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
                                    ),
                                    GestureDetector(
                                      onTap: () => _getCurrentLocation(setSheetState),
                                      child: Text('Retry', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                                    ),
                                  ],
                                ),
                    ),

                    const SizedBox(height: 16),

                    // Photo Section
                    Text(
                      'Photo Evidence (Optional)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedImage == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.camera, setSheetState),
                              icon: const Icon(Icons.camera_alt_outlined, size: 20),
                              label: Text('Camera', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.errorColor,
                                side: const BorderSide(color: AppTheme.outlineVariant),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickImage(ImageSource.gallery, setSheetState),
                              icon: const Icon(Icons.photo_library_outlined, size: 20),
                              label: Text('Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.errorColor,
                                side: const BorderSide(color: AppTheme.outlineVariant),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedImage!,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setSheetState(() => _selectedImage = null);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Send Button
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : () => _submitEmergency(sheetContext, setSheetState),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_rounded, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Send Emergency SOS',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return AppTheme.successColor;
      case 'dispatched':
        return Colors.blue.shade700;
      case 'cancelled':
        return AppTheme.onSurfaceVariant;
      case 'pending':
      default:
        return AppTheme.errorColor;
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return 'RESOLVED';
      case 'dispatched':
        return 'DISPATCHED';
      case 'cancelled':
        return 'CANCELLED';
      case 'pending':
      default:
        return 'PENDING';
    }
  }

  String _emergencyIcon(String type) {
    switch (type.toLowerCase()) {
      case 'medical':
        return '🏥';
      case 'accident':
        return '🚨';
      case 'breakdown':
        return '🔧';
      default:
        return '❓';
    }
  }

  String _emergencyTitle(String type) {
    switch (type.toLowerCase()) {
      case 'medical':
        return 'Medical Emergency';
      case 'accident':
        return 'Accident';
      case 'breakdown':
        return 'Vehicle Breakdown';
      default:
        return 'Emergency';
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 200,
                  color: Colors.white,
                  child: const Center(child: Text('Image not available')),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Emergency SOS',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppTheme.errorColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const TruckLoaderCenter(color: AppTheme.errorColor, label: 'Loading…')
          : _error != null
              ? _buildErrorState()
              : _emergencies.isEmpty
                  ? _buildEmptyState()
                  : _buildEmergenciesList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEmergencySheet,
        backgroundColor: AppTheme.errorColor,
        icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
        label: Text(
          'Send SOS',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.errorColor),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEmergencies,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadEmergencies,
      color: AppTheme.errorColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 40,
                  color: AppTheme.errorColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No SOS requests sent',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the button below to send an immediate emergency SOS to dispatch control.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmergenciesList() {
    return RefreshIndicator(
      onRefresh: _loadEmergencies,
      color: AppTheme.errorColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16).copyWith(bottom: 100),
        itemCount: _emergencies.length,
        itemBuilder: (context, index) {
          final item = _emergencies[index];
          final date = DateTime.tryParse(item['created_at'] ?? '');
          final formattedDate = date != null
              ? DateFormat('MMM d, y • h:mm a').format(date.toLocal())
              : 'Unknown Date';
          final emergencyType = (item['emergency_type'] ?? 'other').toString();
          final status = (item['status'] ?? 'pending').toString();
          final statusColor = _statusColor(status);
          final imageUrl = item['image_url'] as String?;
          final rescueVehicle = item['dispatched_vehicle_name'] as String?;
          final location = item['location'];

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formattedDate,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(_emergencyIcon(emergencyType), style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      _emergencyTitle(emergencyType),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (item['description'] != null && (item['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item['description'],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                ],
                if (rescueVehicle != null && rescueVehicle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 16, color: Colors.blue),
                        const SizedBox(width: 6),
                        Text(
                          'Rescue: $rescueVehicle',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (location != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 15, color: AppTheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        location is Map && location['lat'] != null
                            ? 'GPS: ${(location['lat'] as num).toStringAsFixed(4)}, ${(location['lng'] as num).toStringAsFixed(4)}'
                            : 'GPS Captured',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _showImageDialog(imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Image.network(
                            imageUrl,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 100,
                              color: AppTheme.surfaceVariant,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.fullscreen, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Tap to view',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}