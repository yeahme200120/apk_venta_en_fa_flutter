import 'package:flutter/material.dart';
import 'core/config/app_theme.dart';
import 'core/services/permission_service.dart';
import 'vistas/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  PermissionService().requestStartupPermissions();
  runApp(const PuntoVentaApp());
}

class PuntoVentaApp extends StatelessWidget {
  const PuntoVentaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: AppTheme.seedColor,
      builder: (context, seedColor, _) => MaterialApp(
        title: 'Vende en FA',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          appBarTheme: AppBarTheme(backgroundColor: seedColor, foregroundColor: Colors.white),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}