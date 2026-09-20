import 'dart:async';

import 'package:flutter/material.dart';

import '../core/database/local_db.dart';
import '../core/network/api_client.dart';
import '../core/services/sync_orchestrator.dart';
import '../core/storage/app_storage.dart';
import 'caja/cash_management_screen.dart';
import 'daily_stats/daily_stats_screen.dart';
import 'operacion/operation_screen.dart';
import 'pos/pos_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/sync_progress_dialog.dart';

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

  // 🆕 Escucha cambios de operación en tiempo real.
  StreamSubscription<void>? _operationSub;

  // 🆕 SYNC: bandera para el botón global de la sección Caja.
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();

    // Inicialización inmediata y síncrona
    _initCashTabController();

    WidgetsBinding.instance.addObserver(this);

    // 🆕 Escucha cambios de operación en tiempo real.
    _operationSub = LocalDb.operationChanges.listen((_) {
      if (mounted) _loadOperationState();
    });

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

    // 🆕 Cancelar suscripción.
    _operationSub?.cancel();
    _operationSub = null;

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

    if (mounted) {
      setState(() {
        _cajasActivas = cached['cajas_activas'] == true;
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
  // SINCRONIZACIÓN GLOBAL (orquestador único)
  // ============================================================
  //
  // Comparte la misma lógica que SettingsScreen.
  //
  //   1. Sube TODO lo pendiente (sync_queue + ventas históricas
  //      + outbox del día) respetando la fecha comercial original.
  //   2. Baja TODO lo que la app necesita.
  //   3. Nunca borra. Solo upsert.
  //
  // El botón está en el AppBar de la sección Caja, por lo que
  // está disponible tanto en "Operación" como en "Movimientos".

  Future<void> _runGlobalSync() async {
    if (_isSyncing) return;

    final storage = AppStorage();

    final companyId = await storage.getEmpresaId() ?? 0;
    final userId = await storage.getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      _snack('No hay empresa o usuario activo.', error: true);
      return;
    }

    if (!mounted) return;

    final businessDateKey = await storage.getServerBusinessDateKey();
    final businessDate = businessDateKey != null && businessDateKey.isNotEmpty
        ? (DateTime.tryParse(businessDateKey) ?? DateTime.now())
        : DateTime.now();

    if (!mounted) return;

    setState(() => _isSyncing = true);

    // ============================================================
    // DIÁLOGO DE PROGRESO
    // ============================================================

    final progressNotifier = ValueNotifier<String>(
      'Iniciando sincronización...',
    );

    NavigatorState? progressNavigator;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          progressNavigator = Navigator.of(ctx, rootNavigator: true);
          return SyncProgressDialog(progressNotifier: progressNotifier);
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final report = await SyncOrchestrator().syncAll(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        onProgress: (stage, message) {
          progressNotifier.value = message;
        },
      );

      // Cerrar diálogo de progreso.
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!mounted) return;

      // ============================================================
      // RESULTADO
      // ============================================================

      if (report.skipped) {
        _snack(report.summary);
      } else if (report.hasErrors) {
        _snack(
          'Sincronización con avisos: '
          '${report.upload.synced}/${report.upload.total} subidas · '
          '${report.download.okCount}/${SyncDownloadReport.totalSteps} bajadas',
          error: true,
        );
      } else {
        _snack(
          'Sincronización completada. '
          'Subidas: ${report.upload.synced}/${report.upload.total} · '
          'Bajadas: ${report.download.okCount}/'
          '${SyncDownloadReport.totalSteps}',
        );
      }

      // Refrescar el estado operativo.
      await _loadOperationState();
    } catch (e) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!mounted) return;

      _snack('Error al sincronizar: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  // ============================================================
  // LÓGICA DE NAVEGACIÓN
  // ============================================================

  bool get _showCajaTab => _cajasActivas;

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
              // 🆕 Botón de sincronización global.
              //
              // Vive en el AppBar de la sección Caja para estar
              // disponible tanto en "Operación" como en "Movimientos".
              //
              // Solo se deshabilita mientras corre una sync.
              actions: [
                IconButton(
                  tooltip: 'Sincronizar todo',
                  onPressed: _isSyncing ? null : _runGlobalSync,
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                ),
              ],
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