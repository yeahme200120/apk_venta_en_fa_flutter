import 'package:flutter/material.dart';

import '../core/network/api_client.dart';
import '../core/storage/app_storage.dart';
import 'caja/cash_management_screen.dart';
import 'daily_stats/daily_stats_screen.dart';
import 'operacion/operation_screen.dart';
import 'pos/pos_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<PosScreenState> _posKey = GlobalKey<PosScreenState>();

  int _currentIndex = 0;
  int _cartCount = 0;

  // Sub-tab dentro de "Caja": 0 = Operación, 1 = Movimientos
  int _cashSubIndex = 0;

  // NO usar late final. Se inicializa en initState y se guarda como nullable.
  TabController? _cashTabController;

  bool _cajasActivas = false;
  bool _esCajero = false;

  @override
  void initState() {
    super.initState();

    // Inicialización inmediata y síncrona
    _initCashTabController();

    WidgetsBinding.instance.addObserver(this);
    _loadOperationState();
  }

  void _initCashTabController() {
    _cashTabController?.removeListener(_onCashTabChanged);
    _cashTabController?.dispose();

    final controller = TabController(length: 2, vsync: this);

    controller.addListener(() {
      if (!mounted) return;
      _onCashTabChanged();
    });

    _cashTabController = controller;
  }

  void _onCashTabChanged() {
    final controller = _cashTabController;
    if (controller == null) return;
    if (controller.index == _cashSubIndex) return;

    setState(() {
      _cashSubIndex = controller.index;
    });
  }

  @override
  void dispose() {
    _cashTabController?.removeListener(_onCashTabChanged);
    _cashTabController?.dispose();
    _cashTabController = null;

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
  }

  // ============================================================
  // LÓGICA DE NAVEGACIÓN
  // ============================================================

  bool get _showCajaTab => _cajasActivas && _esCajero;

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

  Widget _buildCashTab() {
    return IndexedStack(
      index: _cashSubIndex.clamp(0, 1),
      children: const [
        OperationScreen(),
        CashManagementScreen(),
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

  // 🔑 Aquí está el fix: no uses _cajaTabIndex, compara directo.
  final estaEnCaja = _showCajaTab && safeIndex == 2;

  return Scaffold(
    backgroundColor: colors.surface,

    appBar: estaEnCaja
        ? AppBar(
            title: Text(
              _cashSubIndex == 0 ? 'Operación' : 'Movimientos',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            bottom: _cashTabController != null
                ? TabBar(
                    controller: _cashTabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicatorColor: Colors.white,
                    tabs: const [
                      Tab(text: 'Operación'),
                      Tab(text: 'Movimientos'),
                    ],
                  )
                : null,
          )
        : null,

    body: IndexedStack(
      index: safeIndex,
      children: pages,
    ),

    bottomNavigationBar: NavigationBar(
      selectedIndex: safeIndex,
      onDestinationSelected: (index) {
        setState(() => _currentIndex = index);

        if (_showCajaTab && index == 2) {
          _loadOperationState();
        }
      },
      destinations: destinations,
    ),
  );
}
}