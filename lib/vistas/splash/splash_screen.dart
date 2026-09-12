import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../auth/login_screen.dart';
import '../home_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
  });

  @override
  State<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends State<SplashScreen> {
  Timer? _timer;

  final AuthService _authService =
      AuthService();

  @override
  void initState() {
    super.initState();

    _verificarSesion();
  }

  void _verificarSesion() {
    _timer = Timer(
      const Duration(seconds: 2),
      () async {
        if (!mounted) {
          return;
        }

        try {
          final hasSession =
              await _authService.hasSession();

          if (!mounted) {
            return;
          }

          if (hasSession) {
            Navigator.of(context)
                .pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    const HomeShell(),
              ),
            );

            return;
          }

          Navigator.of(context)
              .pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  const LoginScreen(),
            ),
          );
        } catch (_) {
          if (!mounted) {
            return;
          }

          Navigator.of(context)
              .pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  const LoginScreen(),
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor:
          colors.surface,
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 170,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
