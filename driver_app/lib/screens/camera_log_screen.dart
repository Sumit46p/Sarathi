import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';

enum LogType { fuel, maintenance }

class CameraLogScreen extends StatefulWidget {
  final LogType logType;
  const CameraLogScreen({super.key, required this.logType});

  @override
  State<CameraLogScreen> createState() => _CameraLogScreenState();
}

class _CameraLogScreenState extends State<CameraLogScreen> {
  XFile? _image;
  bool _uploading = false;
  final _notesController = TextEditingController();

  bool get _isFuel => widget.logType == LogType.fuel;

  String get _title => _isFuel ? 'Fuel Entry' : 'Maintenance Entry';

  String get _collection => _isFuel ? 'fuel_logs' : 'maintenance_logs';

  // Blue accent used consistently for both entry types.
  Color get _accentColor => AppTheme.primaryColor;

  IconData get _headerIcon =>
      _isFuel ? Icons.local_gas_station_rounded : Icons.build_circle_rounded;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  final ImagePicker _picker = ImagePicker();
  bool _openingCamera = false;

  // Explicit camera capture — user taps to open the device camera.
  Future<void> _captureFromCamera() async {
    // Guard against double-taps opening the camera twice in a row.
    if (_openingCamera) return;
    _openingCamera = true;

    try {
      final granted = await _ensureCameraPermission();
      if (!granted) return;

      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked != null && mounted) {
        setState(() => _image = picked);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      final isPermission = e.code == 'camera_access_denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPermission
                ? 'Camera permission is denied. Please enable it in your device settings.'
                : 'Could not open camera: ${e.message ?? e.code}',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open camera: $e',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      _openingCamera = false;
    }
  }

  // Only triggers the system permission dialog the first time. Once the
  // user has granted (or permanently denied) access, this short-circuits
  // and never asks again.
  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied || status.isRestricted) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Camera access is blocked. Enable it from device Settings to continue.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorColor,
          action: SnackBarAction(
            label: 'Settings',
            textColor: Colors.white,
            onPressed: openAppSettings,
          ),
        ),
      );
      return false;
    }

    // Not yet decided — this is the only point where the OS prompt appears,
    // and it will only appear this one time going forward.
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  Future<void> _submitEntry() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please take a photo first.',
            style: GoogleFonts.plusJakartaSans(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _uploading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance
          .ref()
          .child('$_collection/$uid/$timestamp.jpg');

      await ref.putFile(File(_image!.path));
      final imageUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection(_collection).add({
        'driverId': uid,
        'imageUrl': imageUrl,
        'notes': _notesController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending_review',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_isFuel ? "Fuel" : "Maintenance"} entry submitted to admin.',
              style: GoogleFonts.plusJakartaSans(),
            ),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          _title,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon header — same rounded-chip style as the dashboard.
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_headerIcon, color: _accentColor, size: 48),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _isFuel
                    ? 'Snap a photo of the fuel receipt or meter'
                    : 'Snap a photo of the issue for the record',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Photo preview / capture
            GestureDetector(
              onTap: _captureFromCamera,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLowest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _image == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _accentColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 32,
                              color: _accentColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap to open camera',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Photo required to submit',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppTheme.outline,
                            ),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.file(
                          File(_image!.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
              ),
            ),

            if (_image != null) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _captureFromCamera,
                  icon: Icon(Icons.refresh_rounded, color: _accentColor, size: 18),
                  label: Text(
                    'Retake Photo',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: _accentColor,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Notes
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: TextField(
                controller: _notesController,
                maxLines: 3,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.onSurface),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                  labelText: _isFuel ? 'Fuel amount / notes' : 'Issue description',
                  labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.outline),
                  hintText: _isFuel
                      ? 'e.g. 40 litres at Petrol Pump XYZ'
                      : 'e.g. Brake pads replaced',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.outline.withValues(alpha: 0.6),
                  ),
                  prefixIcon: Icon(Icons.notes_rounded, color: _accentColor),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _uploading ? null : _submitEntry,
                icon: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _uploading ? 'Uploading...' : 'Submit to Admin',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}