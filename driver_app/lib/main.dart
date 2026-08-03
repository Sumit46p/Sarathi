import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sarathi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _loading = true;
  bool _hasToken = false;
  StreamSubscription<void>? _forceLogoutSub;

  @override
  void initState() {
    super.initState();
    _checkAuth();
    // Listen for force-logout events (expired refresh token) so we
    // can navigate to the login screen with a clear message.
    _forceLogoutSub = forceLogoutController.stream.listen((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(sessionExpired: true),
        ),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _forceLogoutSub?.cancel();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    // Validate the stored token against the backend so a stale/expired
    // session never boots the user into a broken dashboard.
    var valid = false;
    try {
      valid = await ApiService.validateSession();
    } catch (_) {
      valid = false;
    }
    if (mounted) {
      setState(() {
        _hasToken = valid;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }
    if (_hasToken) {
      return const DashboardScreen();
    }
    return const SplashScreen();
  }
}
