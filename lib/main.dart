import 'package:flutter/material.dart';

import 'core/config/app_theme.dart';
import 'core/services/network_monitor.dart';
import 'core/services/permission_service.dart';
import 'vistas/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PermissionService().requestStartupPermissions();
  await NetworkMonitor().initialize();

  runApp(const PuntoVentaApp());
}

class PuntoVentaApp extends StatelessWidget {
  const PuntoVentaApp({super.key});

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
                side: BorderSide(
                  color: colorScheme.outlineVariant,
                ),
              ),
            ),

            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.outline,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.outline,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 2,
                ),
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
                TextStyle(
                  color: colorScheme.onSurface,
                ),
              ),
            ),

            chipTheme: ChipThemeData(
              backgroundColor: colorScheme.surfaceContainerHighest,
              selectedColor: colorScheme.primaryContainer,
              side: BorderSide(
                color: colorScheme.outlineVariant,
              ),
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