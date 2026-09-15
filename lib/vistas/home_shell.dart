import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/storage/app_storage.dart';
import 'caja/cash_management_screen.dart';
import 'daily_stats/daily_stats_screen_backup.dart';
import 'operacion/operation_screen.dart';
import 'pos/pos_screen.dart';
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

  // Sub-tab dentro de "Caja": 0 = Operación, 1 = Movimientos
  int _cashSubIndex = 0;

  // ── Estado operativo ────────────────────────────────────────
  bool _cajasActivas = false;
  bool _esCajero = false;

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
    if (state == AppLifecycleState.resumed && mounted) {
      _loadOperationState();
    }
  }

  // ============================================================
  // CARGA DEL ESTADO OPERATIVO
  // ============================================================

  Future<void> _loadOperationState() async {
    final cached = await AppStorage().getOperationState();
    final rolLocal = await AppStorage().getRol();
    final cajeroLocal = await AppStorage().isCajero();

    if (mounted) {
      setState(() {
        _cajasActivas = cached['cajas_activas'] == true;
        _esCajero = cajeroLocal;
      });
    }

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
      // Modo offline o API no disponible.
    }

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

  /// Índice real del tab "Caja" (o -1 si no está visible).
  int get _cajaTabIndex => _showCajaTab ? 2 : -1;

  List<Widget> _buildPages() {
    return [
      PosScreen(
        key: _posKey,
        onCartChanged: (count) {
          if (!mounted) return;
          if (_cartCount == count) return;
          setState(() => _cartCount = count);
        },
      ),
      const DailyStatsScreen(),
      if (_showCajaTab) _buildCashTab(),
      const SettingsScreen(),
    ];
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

  /// Tab "Caja" con dos sub-vistas internas: Operación y Movimientos.
  /// Tab "Caja" con dos sub-vistas internas: Operación y Movimientos.
  Widget _buildCashTab() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ─────────────────────────────────────────────
        // Header con el SegmentedButton bien espaciado
        // ─────────────────────────────────────────────
        Material(
          color: cs.surface,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.tune, size: 16),
                      label: Text('Operación'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 16,
                      ),
                      label: Text('Movimientos'),
                    ),
                  ],
                  selected: {_cashSubIndex},
                  onSelectionChanged: (set) {
                    setState(() => _cashSubIndex = set.first);
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ─────────────────────────────────────────────
        // Contenido del sub-tab
        // ─────────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: _cashSubIndex,
            children: const [OperationScreen(), CashManagementScreen()],
          ),
        ),
      ],
    );
  }
  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pages = _buildPages();
    final destinations = _buildDestinations();

    final safeIndex = _currentIndex.clamp(0, pages.length - 1);

    return Scaffold(
      backgroundColor: colors.surface,
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);

          // Al abrir la tab Caja, refrescar el estado operativo
          // y volver al sub-tab de Operación.
          if (index == _cajaTabIndex) {
            _loadOperationState();
          }
        },
        destinations: destinations,
      ),
    );
  }
}
