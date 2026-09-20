import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/services/auth_service.dart';
// 🆕 UBICACIÓN
import '../../core/services/location_service.dart';
import '../auth/login_screen.dart';
import '../home_shell.dart';

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

    // 🆕 UBICACIÓN:
    // Se solicita el permiso de ubicación en cuanto
    // arranca el splash. No bloquea el flujo normal.
    // Si el usuario rechaza, la app sigue funcionando
    // pero el registro (que exige ubicación) fallará.
    _solicitarPermisoUbicacion();

    _verificarSesion();
  }

  // ============================================================
  // 🆕 UBICACIÓN: PERMISO AL INICIO
  // ============================================================

  Future<void> _solicitarPermisoUbicacion() async {
    try {
      final service = LocationService();

      // 1. Servicio habilitado.
      final enabled = await service.isLocationServiceEnabled();

      if (!enabled) {
        debugPrint('📍 Splash: servicio de ubicación deshabilitado.');
        return;
      }

      // 2. Permiso actual.
      var permission = await service.checkPermission();

      // 3. Solicitar si aún no fue decidido.
      if (permission == LocationPermission.denied) {
        permission = await service.requestPermission();
      }

      // 4. Log del resultado.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('📍 Splash: permiso denegado.');
      } else if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        debugPrint('📍 Splash: permiso concedido.');
      }
    } catch (e) {
      debugPrint('📍 Splash: error solicitando permiso: $e');
    }
  }

  // ============================================================
  // VERIFICAR SESIÓN
  // ============================================================

  void _verificarSesion() {
    _timer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;

      bool hasSession = false;

      try {
        hasSession = await _authService.hasSession();
      } catch (_) {
        hasSession = false;
      }

      // 🔑 CRÍTICO: volver a verificar `mounted` DESPUÉS del await.
      // Sin esto, Flutter lanza:
      //   "Looking up a deactivated widget's ancestor is unsafe."
      if (!mounted) return;

      if (hasSession) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
        return;
      }

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
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