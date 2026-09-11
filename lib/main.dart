import 'package:flutter/material.dart';

import 'core/config/app_theme.dart';
import 'core/services/automatic_sync_service.dart';
import 'core/services/network_monitor.dart';
import 'core/services/permission_service.dart';
import 'vistas/splash/splash_screen.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PermissionService().requestStartupPermissions();

  runApp(const PuntoVentaApp());

  unawaited(NetworkMonitor().initialize());
}

class PuntoVentaApp extends StatefulWidget {
  const PuntoVentaApp({super.key});

  @override
  State<PuntoVentaApp> createState() => _PuntoVentaAppState();
}

class _PuntoVentaAppState extends State<PuntoVentaApp> {
  final AutomaticSyncService _automaticSyncService = AutomaticSyncService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutomaticSync();
    });
  }

  Future<void> _startAutomaticSync() async {
    await _automaticSyncService.start();
  }

  @override
  void dispose() {
    _automaticSyncService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: AppTheme.seedColor,
      builder: (context, seedColor, _) {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        );

        return MaterialApp(
          title: 'Vende en FA',
          debugShowCheckedModeBanner: false,

          theme: ThemeData(
            useMaterial3: true,

            colorScheme: colorScheme,

            scaffoldBackgroundColor: colorScheme.surface,

            appBarTheme: AppBarTheme(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 0,
            ),

            cardTheme: CardThemeData(
              color: colorScheme.surface,
              elevation: 2,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),

            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: colorScheme.surface,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outline),
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.outline),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            navigationBarTheme: NavigationBarThemeData(
              indicatorColor: colorScheme.primaryContainer,

              backgroundColor: colorScheme.surface,

              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(color: colorScheme.onSurface),
              ),
            ),

            chipTheme: ChipThemeData(
              backgroundColor: colorScheme.surfaceContainerHighest,

              selectedColor: colorScheme.primaryContainer,

              side: BorderSide(color: colorScheme.outlineVariant),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          home: const SplashScreen(),
        );
      },
    );
  }
}
