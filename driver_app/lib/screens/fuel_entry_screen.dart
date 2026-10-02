import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/truck_loader.dart';

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
  String? _assignedVehicleFuelType;

  final _formKey = GlobalKey<FormState>();
  final _litersController = TextEditingController();
  final _odometerController = TextEditingController();
  final _notesController = TextEditingController();
  final _costController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  XFile? _receiptImage;

  String _selectedFuelType = 'petrol';

  @override
  void initState() {
    super.initState();
    _loadFuelEntries();
  }

  @override
  void dispose() {
    _litersController.dispose();
    _odometerController.dispose();
    _notesController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _loadFuelEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final entries = await ApiService.getFuelEntries();
      try {
        final profile = await ApiService.getDriverMe();
        final vehicle = profile?['assigned_vehicle'] as Map<String, dynamic>?;
        if (vehicle != null && vehicle['fuel_type'] != null) {
          _assignedVehicleFuelType = vehicle['fuel_type'].toString().toLowerCase();
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _fuelEntries = entries;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fuelEntries = [];
          _isLoading = false;
          _error = 'Could not load fuel entries. Please try again.';
        });
      }
    }
  }

  void _handleFuelTypeChange(String fuelType) {
    setState(() {
      _selectedFuelType = fuelType;
      // Clear price when switching type so user enters the correct price
      _costController.clear();
    });
  }

  String _costUnitLabel() {
    switch (_selectedFuelType) {
      case 'ev':
        return 'Cost per kWh (रु)';
      default:
        return 'Cost per Liter (रु)';
    }
  }

  String _quantityLabel() {
    switch (_selectedFuelType) {
      case 'ev':
        return 'Energy Charged (kWh)';
      default:
        return 'Liters';
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1280,
      );
      if (picked != null && mounted) {
        setState(() => _receiptImage = picked);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open camera: ${e.message}'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _clearReceipt() {
    setState(() => _receiptImage = null);
  }

  Future<void> _submitFuelEntry() async {
    if (!_formKey.currentState!.validate()) return;

    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please take a receipt / charging photo.'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);

    final quantity = double.tryParse(_litersController.text) ?? 0;
    final costPerUnit = double.tryParse(_costController.text) ?? 0;
    final odometer = double.tryParse(_odometerController.text);
    final notes = _notesController.text;

    if (costPerUnit <= 0) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid price per unit.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final liters = quantity;

    final success = await ApiService.createFuelLog(
      fuelType: _selectedFuelType,
      liters: liters,
      costPerLiter: costPerUnit,
      odometerReading: odometer,
      notes: notes,
      receiptImagePath: _receiptImage!.path,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);

      if (success) {
        Navigator.of(context).pop(); // Close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Fuel entry logged successfully!'),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
        _loadFuelEntries(); // Reload list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save fuel entry. Check your receipt photo and try again.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _showAddEntrySheet() {
    _litersController.clear();
    _odometerController.clear();
    _notesController.clear();
    _costController.clear();
    _receiptImage = null;
    if (_assignedVehicleFuelType == 'ev') {
      _selectedFuelType = 'ev';
    } else if (_assignedVehicleFuelType == 'diesel') {
      _selectedFuelType = 'diesel';
    } else {
      _selectedFuelType = 'petrol';
    }

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
                        Text(
                          _selectedFuelType == 'ev' ? 'New EV Charging Entry' : 'New Fuel Entry',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Fuel / Energy Type
                    Text(
                      'Fuel / Energy Type',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFuelTypeChip('petrol', 'Petrol ⛽', setSheetState),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFuelTypeChip('diesel', 'Diesel ⛽', setSheetState),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFuelTypeChip('ev', 'EV ⚡', setSheetState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Quantity (Liters or kWh)
                    TextFormField(
                      controller: _litersController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: _quantityLabel(),
                        prefixIcon: Icon(
                          _selectedFuelType == 'ev'
                              ? Icons.bolt_outlined
                              : Icons.water_drop_outlined,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Required';
                        final v = double.tryParse(val);
                        if (v == null || v <= 0) return 'Enter a valid quantity';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Cost per unit (manual entry)
                    TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: _costUnitLabel(),
                        prefixText: 'रु ',
                        prefixIcon: Icon(
                          _selectedFuelType == 'ev'
                              ? Icons.electric_bolt
                              : Icons.local_gas_station_outlined,
                          color: _selectedFuelType == 'ev'
                              ? Colors.amber
                              : AppTheme.primaryColor,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        helperText: _selectedFuelType == 'ev'
                            ? 'Enter charging price per kWh'
                            : 'Enter current fuel price per litre',
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Required';
                        final v = double.tryParse(val);
                        if (v == null || v <= 0) return 'Enter a valid price';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Total Amount
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedFuelType == 'ev' ? 'Total Charging Cost' : 'Total Fuel Cost',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            'रु ${((double.tryParse(_litersController.text) ?? 0) * (double.tryParse(_costController.text) ?? 0)).toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _selectedFuelType == 'ev' ? Colors.amber.shade700 : AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Odometer
                    TextFormField(
                      controller: _odometerController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Odometer Reading (km)',
                        prefixIcon: const Icon(Icons.speed_outlined),
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
                    const SizedBox(height: 20),

                    // Receipt / Charging photo
                    Text(
                      _selectedFuelType == 'ev' ? 'Charging Receipt Photo *' : 'Fuel Receipt Photo *',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_receiptImage == null)
                      GestureDetector(
                        onTap: _pickReceipt,
                        child: Container(
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.errorColor.withOpacity(0.5),
                              width: 1.5,
                            ),
                            color: AppTheme.errorLight.withOpacity(0.5),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                size: 40,
                                color: AppTheme.errorColor,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Take a photo of the fuel receipt',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppTheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Required',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.errorColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_receiptImage!.path),
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: _clearReceipt,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
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
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Save Entry',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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

  Widget _buildFuelTypeChip(String value, String label, StateSetter setSheetState) {
    final isSelected = _selectedFuelType == value;
    Color selectedColor;
    switch (value) {
      case 'ev':
        selectedColor = Colors.green.shade600;
        break;
      default:
        selectedColor = AppTheme.primaryColor;
    }
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setSheetState(() {
          _handleFuelTypeChange(value);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.onSurface,
          ),
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
          'Fuel & Energy Entries',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const TruckLoaderCenter()
          : _error != null
              ? _buildErrorState()
              : _fuelEntries.isEmpty
                  ? _buildEmptyState()
                  : _buildEntriesList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEntrySheet,
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Add Entry', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
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
            style: GoogleFonts.inter(color: AppTheme.errorColor),
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.local_gas_station_outlined,
              size: 40,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No fuel or energy entries yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to add your first entry.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesList() {
    return RefreshIndicator(
      onRefresh: _loadFuelEntries,
      color: AppTheme.primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16).copyWith(bottom: 100),
        itemCount: _fuelEntries.length,
        itemBuilder: (context, index) {
          final entry = _fuelEntries[index];
          final isEv = entry['fuel_type'] == 'ev';
          final date = DateTime.tryParse(entry['created_at'] ?? '');
          final formattedDate = date != null ? DateFormat('MMM d, y • h:mm a').format(date.toLocal()) : 'Unknown Date';
          final receiptUrl = entry['receipt_image_url'] as String?;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                        color: isEv ? Colors.green.withOpacity(0.12) : AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'रु ${entry['amount']}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: isEv ? Colors.green.shade700 : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (entry['odometer_reading'] != null) ...[
                  _buildInfoRow(
                    Icons.speed_outlined,
                    '${entry['odometer_reading']} km',
                  ),
                  const SizedBox(height: 12),
                ],
                _buildInfoRow(
                  isEv ? Icons.electric_bolt : Icons.water_drop_outlined,
                  isEv
                      ? '${entry['liters']} kWh • EV Charging'
                      : '${entry['liters']} L • ${entry['fuel_type'] ?? 'Fuel'}',
                ),
                if (receiptUrl != null && receiptUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      receiptUrl,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: AppTheme.surfaceVariant,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 120,
                          color: AppTheme.surfaceVariant,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (entry['notes'] != null && entry['notes'].isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    entry['notes'],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
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

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}