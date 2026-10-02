import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/animations.dart';
import '../widgets/truck_loader.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  List<dynamic> _records = [];
  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadMaintenance();
  }

  Future<void> _loadMaintenance() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final records = await ApiService.getMaintenanceRecords();
      if (!mounted) return;
      setState(() {
        _records = records;
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
        _errorMsg = 'Failed to load maintenance records.';
      });
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppTheme.secondaryColor;
      case 'overdue':
        return AppTheme.errorColor;
      case 'pending':
      default:
        return AppTheme.warningColor;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _confirmDelete(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Record', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text(
          'Are you sure you want to delete this maintenance request?',
          style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ApiService.deleteMaintenanceRecord(id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Maintenance record deleted', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
          _loadMaintenance();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete record', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    }
  }

  void _showAddMaintenanceSheet() {
    final descriptionController = TextEditingController();
    final costController = TextEditingController();
    File? selectedImage;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
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
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.build_rounded, color: AppTheme.primaryColor, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Request Maintenance',
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
                  const SizedBox(height: 18),

                  Text(
                    'Maintenance Details *',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    maxLines: 4,
                    minLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Describe the maintenance issue or service required...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
                      filled: true,
                      fillColor: AppTheme.surfaceVariant.withOpacity(0.5),
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
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                    ),
                    style: GoogleFonts.inter(color: AppTheme.onSurface),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Estimated Cost (Optional)',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: costController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: 'रु ',
                      prefixStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      hintText: 'Estimated cost in NPR',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
                      filled: true,
                      fillColor: AppTheme.surfaceVariant.withOpacity(0.5),
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
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                      ),
                    ),
                    style: GoogleFonts.inter(color: AppTheme.onSurface),
                  ),
                  const SizedBox(height: 18),

                  Text(
                    'Attach Photo (Optional)',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selectedImage == null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );
                              if (image != null) {
                                setSheetState(() {
                                  selectedImage = File(image.path);
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt_outlined, size: 20),
                            label: Text('Camera', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
                              side: const BorderSide(color: AppTheme.outlineVariant),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 80,
                              );
                              if (image != null) {
                                setSheetState(() {
                                  selectedImage = File(image.path);
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library_outlined, size: 20),
                            label: Text('Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.primaryColor,
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
                            selectedImage!,
                            height: 140,
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
                              setSheetState(() => selectedImage = null);
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

                  // Green Submit Button
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            if (descriptionController.text.trim().isEmpty && selectedImage == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please provide a description or image', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                  backgroundColor: AppTheme.errorColor,
                                ),
                              );
                              return;
                            }

                            setSheetState(() => isSubmitting = true);

                            final success = await ApiService.submitMaintenanceRequest(
                              description: descriptionController.text.trim().isEmpty
                                  ? 'Maintenance request (image attached)'
                                  : descriptionController.text.trim(),
                              imagePath: selectedImage?.path,
                              cost: costController.text.trim(),
                            );

                            if (!sheetContext.mounted) return;
                            setSheetState(() => isSubmitting = false);

                            if (success) {
                              Navigator.of(sheetContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Maintenance request submitted successfully', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                  backgroundColor: AppTheme.successColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                              await _loadMaintenance();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to send maintenance request. Please try again.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                  backgroundColor: AppTheme.errorColor,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Submit Request',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
          'Maintenance Requests',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const TruckLoaderCenter()
          : _errorMsg != null
              ? Center(
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
                          onPressed: _loadMaintenance,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('Retry', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMaintenance,
                  color: AppTheme.primaryColor,
                  child: _records.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.75,
                            alignment: Alignment.center,
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
                                      color: AppTheme.primaryColor.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.build_circle_rounded, size: 48, color: AppTheme.primaryColor),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'No maintenance records',
                                  style: GoogleFonts.inter(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap the button below to request maintenance for your vehicle.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppTheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16).copyWith(bottom: 100),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final record = _records[index];
                            final isOverdue = record['is_overdue'] == true;
                            final status = record['completed'] ? 'completed' : (isOverdue ? 'overdue' : 'pending');
                            final statusColor = _statusColor(status);
                            final imageUrl = record['image_url'] as String?;

                            return AnimatedListItem(
                              index: index,
                              delay: const Duration(milliseconds: 60),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 14),
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
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  status == 'completed'
                                                      ? Icons.check_circle_rounded
                                                      : status == 'overdue'
                                                          ? Icons.warning_rounded
                                                          : Icons.pending_rounded,
                                                  color: statusColor,
                                                  size: 14,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  status.toUpperCase(),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: statusColor,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              if (record['vehicle_name'] != null)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryColor.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    record['vehicle_name'].toString(),
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppTheme.primaryColor,
                                                    ),
                                                  ),
                                                ),
                                              if (status == 'pending') ...[
                                                const SizedBox(width: 8),
                                                InkWell(
                                                  onTap: () => _confirmDelete(record['id']),
                                                  borderRadius: BorderRadius.circular(20),
                                                  child: Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.errorColor.withOpacity(0.08),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.delete_outline_rounded,
                                                      size: 18,
                                                      color: AppTheme.errorColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          const Icon(Icons.build_rounded, size: 16, color: AppTheme.primaryColor),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              record['maintenance_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'MAINTENANCE',
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (record['description'] != null && record['description'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Icon(Icons.notes_rounded, size: 15, color: AppTheme.onSurfaceVariant),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                record['description'].toString(),
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: AppTheme.onSurface,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      const Divider(height: 1, color: AppTheme.outlineVariant),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Due Date',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.onSurfaceVariant,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _formatDate(record['due_date']),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: isOverdue ? AppTheme.errorColor : AppTheme.onSurface,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (record['completed_at'] != null) ...[
                                            Container(
                                              width: 1,
                                              height: 36,
                                              color: AppTheme.outlineVariant,
                                            ),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(left: 14),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Completed',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppTheme.onSurfaceVariant,
                                                        letterSpacing: 0.3,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _formatDate(record['completed_at']),
                                                      style: GoogleFonts.inter(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w600,
                                                        color: AppTheme.secondaryColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (record['cost'] != null) ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            const Icon(Icons.payments_outlined, size: 16, color: AppTheme.primaryColor),
                                            const SizedBox(width: 8),
                                            Text(
                                              'रु ${record['cost']}',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primaryColor,
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
                                                  height: 130,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) =>
                                                      const SizedBox.shrink(),
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
                                ),
                              ),
                            );
                          },
                        ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMaintenanceSheet,
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Request Maintenance',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
