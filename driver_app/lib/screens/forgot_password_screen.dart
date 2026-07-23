import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/custom_buttons.dart';
import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _organizationController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMsg;
  String? _successMsg;

  Future<void> _handleVerifyIdentity() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
        _successMsg = null;
      });

      final success = await ApiService.verifyForgotPasswordIdentity(
        username: _usernameController.text.trim(),
        organizationName: _organizationController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        setState(() {
          _successMsg = 'Identity verified. Set your new password.';
          _errorMsg = null;
        });
      } else {
        setState(() {
          _errorMsg = 'Verification failed. Check username and organization name.';
          _successMsg = null;
        });
      }
    }
  }

  Future<void> _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMsg = null;
        _successMsg = null;
      });

      final success = await ApiService.resetPassword(
        username: _usernameController.text.trim(),
        organizationName: _organizationController.text.trim(),
        newPassword: _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      } else {
        setState(() {
          _errorMsg = 'Failed to reset password. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _organizationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = _successMsg != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_reset_rounded, size: 48, color: AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isVerified ? 'Reset Password' : 'Verify Identity',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isVerified
                        ? 'Enter your new password below to complete the reset.'
                        : 'Enter your username and organization name to verify your identity.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_errorMsg != null) ...[
                    Text(_errorMsg!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  if (_successMsg != null) ...[
                    Text(_successMsg!, style: const TextStyle(color: Colors.green), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _usernameController,
                    enabled: !isVerified,
                    decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _organizationController,
                    enabled: !isVerified,
                    decoration: const InputDecoration(labelText: 'Organization Name', prefixIcon: Icon(Icons.business_outlined)),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  if (isVerified) ...[
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'New Password', prefixIcon: Icon(Icons.lock_outline)),
                      validator: (v) => v!.length < 6 ? 'Min 6 chars' : null,
                    ),
                    const SizedBox(height: 32),
                    PrimaryButton(
                      text: 'Reset Password',
                      isLoading: _isLoading,
                      onPressed: _handleResetPassword,
                    ),
                  ] else ...[
                    PrimaryButton(
                      text: 'Verify Identity',
                      isLoading: _isLoading,
                      onPressed: _handleVerifyIdentity,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
