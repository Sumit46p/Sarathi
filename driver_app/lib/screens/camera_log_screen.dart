import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';

class CameraLogScreen extends StatelessWidget {
  final String logType;
  const CameraLogScreen({super.key, required this.logType});

  @override
  Widget build(BuildContext context) {
    final title = logType == 'fuel' ? 'Fuel Entry' : 'Report Issue';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_rounded, size: 48, color: AppTheme.outline),
              const SizedBox(height: 16),
              Text('$title coming soon', style: GoogleFonts.plusJakartaSans(fontSize: 16, color: AppTheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
