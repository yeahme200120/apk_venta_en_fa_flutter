import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../auth/login_screen.dart';
import '../pos/pos_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();

    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    // Mantener el splash visible durante 2 segundos.
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    try {
      final hasSession = await _authService.hasSession();

      if (!mounted) return;

      if (hasSession) {
        // ========================================================
        // SESIÓN EXISTENTE
        // ========================================================
        //
        // El usuario ya inició sesión anteriormente.
        // No mostramos nuevamente el Login.
        //
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const PosScreen(),
          ),
        );
      } else {
        // ========================================================
        // SIN SESIÓN
        // ========================================================
        //
        // Es necesario iniciar sesión.
        //
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
          ),
        );
      }
    } catch (e) {
      // Si ocurre algún problema leyendo la sesión,
      // mandamos al usuario al Login por seguridad.

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
