import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../widgets/custom_buttons.dart';
import '../services/api_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedDepartment;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _licenseUploaded = false;
  File? _licenseImage;

  final ImagePicker _picker = ImagePicker();

  final List<String> _departments = [
    'Ambulance Service',
    'Logistics',
    'Municipal Fleet',
    'Emergency Response',
  ];

  void _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      if (!_licenseUploaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload your license document.'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // ── Persist driver profile to PostgreSQL via Django backend ──
        final uid = credential.user?.uid ?? '';
        final saved = await ApiService.registerDriver(
          firebaseUid: uid,
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          vehicleNumber: _vehicleController.text.trim(),
          department: _selectedDepartment ?? '',
        );

        // If license was picked, record its local path as document metadata.
        // (URL will be empty until you integrate Firebase Storage upload.)
        if (_licenseImage != null) {
          await ApiService.recordDocument(
            firebaseUid: uid,
            docType: 'driving_license',
            fileUrl: _licenseImage!.path, // local path; replace with Storage URL
            fileName: 'driving_license.jpg',
          );
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saved
                    ? 'Account created and saved to database!'
                    : 'Account created! (Database sync pending)',
              ),
              backgroundColor:
                  saved ? AppTheme.successColor : AppTheme.warningColor,
            ),
          );
          Navigator.of(context).pop();
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'An error occurred during sign up'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickLicenseImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (picked != null) {
        setState(() {
          _licenseImage = File(picked.path);
          _licenseUploaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? 'Camera permission denied or unavailable.'
                  : 'Gallery permission denied or unavailable.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLicenseSourceSheet() {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Text(
                  'Upload Driving License',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: Icon(Icons.photo_camera_outlined,
                        color: AppTheme.primaryColor),
                  ),
                  title: const Text('Take a Photo'),
                  subtitle: const Text('Use your camera'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickLicenseImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: Icon(Icons.photo_library_outlined,
                        color: AppTheme.primaryColor),
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text('Pick an existing image'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _pickLicenseImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- shared field decoration ----------
  InputDecoration _decoration(BuildContext context, String label, IconData icon,
      {Widget? suffix}) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: onSurface.withOpacity(0.5)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: onSurface.withOpacity(0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: onSurface.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---------- Header ----------
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.transparent,
                      backgroundImage: AssetImage('assets/images/logo.png'),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create an Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Join Sarathi as a fleet driver',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: onSurface.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 36),

                // ---------- Personal details ----------
                _sectionHeader(context, 'PERSONAL DETAILS'),
                TextFormField(
                  controller: _nameController,
                  decoration:
                      _decoration(context, 'Full Name', Icons.person_outline),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      _decoration(context, 'Email', Icons.email_outlined),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration:
                      _decoration(context, 'Phone Number', Icons.phone_outlined),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 28),

                // ---------- Fleet details ----------
                _sectionHeader(context, 'FLEET DETAILS'),
                TextFormField(
                  controller: _vehicleController,
                  decoration: _decoration(
                      context, 'Vehicle Number', Icons.directions_car_outlined),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDepartment,
                  decoration: _decoration(
                      context, 'Department', Icons.business_outlined),
                  items: _departments.map((String dept) {
                    return DropdownMenuItem<String>(
                      value: dept,
                      child: Text(dept),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedDepartment = newValue;
                    });
                  },
                  validator: (value) => value == null ? 'Required' : null,
                ),
                const SizedBox(height: 14),

                // ---------- License upload ----------
                InkWell(
                  onTap: _showLicenseSourceSheet,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _licenseUploaded
                            ? AppTheme.successColor
                            : onSurface.withOpacity(0.12),
                        width: _licenseUploaded ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      color: _licenseUploaded
                          ? AppTheme.successColor.withOpacity(0.08)
                          : Theme.of(context).colorScheme.surface,
                    ),
                    child: Row(
                      children: [
                        if (_licenseUploaded && _licenseImage != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _licenseImage!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Icon(
                            Icons.upload_file_outlined,
                            size: 22,
                            color: onSurface.withOpacity(0.55),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _licenseUploaded
                                ? 'License Uploaded'
                                : 'Upload Driving License',
                            style: TextStyle(
                              color: _licenseUploaded
                                  ? AppTheme.successColor
                                  : onSurface.withOpacity(0.75),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_licenseUploaded)
                          Icon(Icons.check_circle,
                              size: 20, color: AppTheme.successColor)
                        else
                          Icon(Icons.chevron_right,
                              size: 20, color: onSurface.withOpacity(0.3)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ---------- Security ----------
                _sectionHeader(context, 'SECURITY'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _decoration(
                    context,
                    'Password',
                    Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                        color: onSurface.withOpacity(0.5),
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (value.length < 6) return 'Must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: _decoration(
                    context,
                    'Confirm Password',
                    Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                        color: onSurface.withOpacity(0.5),
                      ),
                      onPressed: () => setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 36),

                // ---------- Sign Up Button ----------
                PrimaryButton(
                  text: 'Sign Up',
                  isLoading: _isLoading,
                  onPressed: _handleSignup,
                ),
                const SizedBox(height: 24),

                // ---------- Login Link ----------
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account? ",
                      style: TextStyle(
                        color: onSurface.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}