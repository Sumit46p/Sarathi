import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';

class FuelEntryScreen extends StatefulWidget {
  const FuelEntryScreen({super.key});

  @override
  State<FuelEntryScreen> createState() => _FuelEntryScreenState();
}

class _FuelEntryScreenState extends State<FuelEntryScreen> {
  bool _isLoading = true;
  List<dynamic> _fuelEntries = [];
  String? _error;
  bool _isSubmitting = false;

  final _formKey = GlobalKey<FormState>();
  final _litersController = TextEditingController();
  final _costController = TextEditingController();
  final _odometerController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFuelEntries();
  }

  @override
  void dispose() {
    _litersController.dispose();
    _costController.dispose();
    _odometerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadFuelEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final entries = await ApiService.getFuelEntries();
      if (mounted) {
        setState(() {
          _fuelEntries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load fuel entries';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitFuelEntry() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);

    final liters = double.tryParse(_litersController.text) ?? 0;
    final cost = double.tryParse(_costController.text) ?? 0;
    final odometer = double.tryParse(_odometerController.text);
    final notes = _notesController.text;

    final success = await ApiService.createFuelEntry(
      liters: liters,
      costPerLiter: cost,
      odometerKm: odometer,
      notes: notes,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      
      if (success) {
        Navigator.of(context).pop(); // Close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fuel entry logged successfully!'),
            backgroundColor: AppTheme.primaryColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadFuelEntries(); // Reload list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save fuel entry.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAddEntrySheet() {
    _litersController.clear();
    _costController.clear();
    _odometerController.clear();
    _notesController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'New Fuel Entry',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Liters and Cost Row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _litersController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Liters',
                              prefixIcon: const Icon(Icons.local_gas_station_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Required';
                              if (double.tryParse(val) == null) return 'Invalid';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _costController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Cost/Liter (NPR)',
                              prefixText: 'रु ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Required';
                              if (double.tryParse(val) == null) return 'Invalid';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Odometer
                    TextFormField(
                      controller: _odometerController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Odometer Reading (km)',
                        prefixIcon: const Icon(Icons.speed_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Notes
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Submit Button
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : () {
                        setSheetState(() => _isSubmitting = true);
                        _submitFuelEntry().whenComplete(() {
                          if (mounted) setSheetState(() => _isSubmitting = false);
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Save Entry',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Fuel Entries',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : _fuelEntries.isEmpty
                  ? _buildEmptyState()
                  : _buildEntriesList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEntrySheet,
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Add Fuel', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppTheme.errorColor),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.plusJakartaSans(color: AppTheme.errorColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadFuelEntries,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_gas_station_rounded, size: 64, color: AppTheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'No fuel entries yet.',
            style: GoogleFonts.plusJakartaSans(fontSize: 16, color: AppTheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first entry.',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesList() {
    return RefreshIndicator(
      onRefresh: _loadFuelEntries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16).copyWith(bottom: 100),
        itemCount: _fuelEntries.length,
        itemBuilder: (context, index) {
          final entry = _fuelEntries[index];
          final date = DateTime.tryParse(entry['fueled_at'] ?? '');
          final formattedDate = date != null ? DateFormat('MMM d, y • h:mm a').format(date.toLocal()) : 'Unknown Date';
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formattedDate,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurface,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'रु ${entry['total_cost']}',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoRow(Icons.local_gas_station_outlined, '${entry['liters']} L'),
                      ),
                      Expanded(
                        child: _buildInfoRow(Icons.attach_money_rounded, 'रु ${entry['cost_per_liter']}/L'),
                      ),
                    ],
                  ),
                  if (entry['odometer_km'] != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.speed_rounded, '${entry['odometer_km']} km'),
                  ],
                  if (entry['notes'] != null && entry['notes'].isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      entry['notes'],
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.outline,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.outline),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppTheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
