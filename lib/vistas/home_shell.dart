import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/storage/app_storage.dart';
import 'pos/pos_screen.dart';
import 'daily_stats/daily_stats_screen.dart';
import 'operacion/operation_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final GlobalKey<PosScreenState> _posKey = GlobalKey<PosScreenState>();

  int _currentIndex = 0;
  int _cartCount = 0;

  // ── Estado operativo ────────────────────────────────────────
  // Controla si se muestra la tab Caja.
  bool _cajasActivas = false;
  bool _esCajero = false;  // cajero | admin | superadmin

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadOperationState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a primer plano, refrescar estado operativo.
    if (state == AppLifecycleState.resumed && mounted) {
      _loadOperationState();
    }
  }

  // ============================================================
  // CARGA DEL ESTADO OPERATIVO
  // ============================================================

  Future<void> _loadOperationState() async {
    // 1. Usar el caché local mientras llega la respuesta remota.
    final cached = await AppStorage().getOperationState();
    final rolLocal = await AppStorage().getRol();
    final cajeroLocal = await AppStorage().isCajero();

    if (mounted) {
      setState(() {
        _cajasActivas = cached['cajas_activas'] == true;
        _esCajero = cajeroLocal;
      });
    }

    // 2. Intentar actualizar desde la API (offline-safe).
    try {
      final offline = await AppStorage().isOfflineSession();
      if (!offline) {
        final state = await ApiClient().getOperationStatus();
        await AppStorage().saveOperationState(state);

        if (mounted) {
          setState(() {
            _cajasActivas = state['cajas_activas'] == true;
          });
        }
      }
    } catch (_) {
      // Modo offline o API no disponible: usa caché ya aplicado.
    }

    // 3. Si el rol aún no está guardado (sesiones previas), intentar leerlo
    //    desde AppStorage como fallback (no tiene método remoto aquí).
    if (rolLocal == null) {
      // Nada que hacer hasta que el usuario vuelva a hacer login online.
    }
  }

  // ============================================================
  // LÓGICA DE NAVEGACIÓN
  // ============================================================

  /// La tab Caja solo se muestra cuando:
  ///   - cajas_activas == true  (configuración de la empresa)
  ///   - el usuario tiene rol cajero, admin o superadmin
  bool get _showCajaTab => _cajasActivas && _esCajero;

  // Índices reales según si la tab Caja está visible o no.
  // Sin Caja: [0=Venta, 1=Stats, 2=Admin]
  // Con Caja:  [0=Venta, 1=Stats, 2=Caja, 3=Admin]
  List<Widget> _buildPages() {
    final pages = <Widget>[
      PosScreen(
        key: _posKey,
        onCartChanged: (count) {
          if (!mounted) return;
          if (_cartCount == count) return;
          setState(() => _cartCount = count);
        },
      ),
      const DailyStatsScreen(),
      if (_showCajaTab) const OperationScreen(),
      const SettingsScreen(),
    ];
    return pages;
  }

  List<NavigationDestination> _buildDestinations() {
    return [
      const NavigationDestination(
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
        label: 'Venta',
      ),
      const NavigationDestination(
        icon: Icon(Icons.analytics_outlined),
        selectedIcon: Icon(Icons.analytics),
        label: 'Estadísticas',
      ),
      if (_showCajaTab)
        const NavigationDestination(
          icon: Icon(Icons.store_outlined),
          selectedIcon: Icon(Icons.store),
          label: 'Caja',
        ),
      const NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings),
        label: 'Admin',
      ),
    ];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pages = _buildPages();
    final destinations = _buildDestinations();

    // Proteger el índice si cambió el número de tabs.
    final safeIndex = _currentIndex.clamp(0, pages.length - 1);

    return Scaffold(
      backgroundColor: colors.surface,
      body: IndexedStack(
        index: safeIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);

          // Al abrir la tab Caja, refrescar el estado operativo.
          final cajaTabIndex = _showCajaTab ? 2 : -1;
          if (index == cajaTabIndex) {
            _loadOperationState();
          }
        },
        destinations: destinations,
      ),
    );
  }
}
