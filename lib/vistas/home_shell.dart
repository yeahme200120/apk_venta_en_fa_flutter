import 'package:flutter/material.dart';

// ✅ Importaciones faltantes agregadas
import '../core/database/local_db.dart';
import '../core/network/network_monitor.dart';
import '../core/services/automatic_sync_service.dart';
import '../core/services/daily_cleanup_service.dart';
import '../core/services/sync_service.dart';
import '../core/storage/app_storage.dart';

import 'daily_stats/daily_stats_screen.dart';
import 'pos/pos_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final NetworkMonitor _networkMonitor = NetworkMonitor();
  final AutomaticSyncService _automaticSyncService = AutomaticSyncService();

  int _selectedIndex = 0;
  bool _initialized = false;
  String? _initError;

  List<Widget> get _pages => [
        const PosScreen(key: ValueKey('pos')),
        const DailyStatsScreen(key: ValueKey('stats')),
        const SettingsScreen(key: ValueKey('settings')),
      ];

  @override
  void initState() {
    super.initState();
    _networkMonitor.addListener(_handleNetworkChange);
    _initialize();
  }

  @override
  void dispose() {
    _networkMonitor.removeListener(_handleNetworkChange);
    super.dispose();
  }

  void _handleNetworkChange() {
    if (!mounted) return;
    setState(() {});
  }

  // ============================================================
  // INICIALIZACIÓN SEGURA
  // ============================================================

  Future<void> _initialize() async {
    try {
      await _networkMonitor.initialize();
      if (!mounted) return;

      await _bootstrapBusinessDay();
      if (!mounted) return;

      await _startAutomaticSync();
      if (!mounted) return;

      setState(() {
        _initialized = true;
        _initError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('❌ Error en _initialize: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        setState(() {
          _initialized = true;
          _initError = 'Error al inicializar: $error';
        });
      }
    }
  }

  // ============================================================
  // BOOTSTRAP DEL DÍA (CORREGIDO: usa SyncService)
  // ============================================================

  Future<void> _bootstrapBusinessDay() async {
    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;
      if (companyId == 0 || userId == 0) {
        debugPrint('⚠️ Empresa o usuario no disponibles.');
        return;
      }

      final today = DateTime.now();
      final lastDate = await AppStorage().getLastBusinessDate();
      final todayStr = today.toIso8601String().substring(0, 10);
      final isNewDay = lastDate == null || lastDate != todayStr;

      if (isNewDay) {
        debugPrint('🔄 Nuevo día detectado: $todayStr');

        await DailyCleanupService().prepareNewBusinessDay(
          companyId: companyId,
          userId: userId,
          businessDate: today,
        );
        if (!mounted) return;

        await AppStorage().saveLastBusinessDate(today);
        if (!mounted) return;

        if (_networkMonitor.isOnline) {
          try {
            // ✅ Ahora usa SyncService (guarda en LocalDb, no en la base diaria)
            await SyncService().syncCatalogs();
            debugPrint('✅ Catálogos sincronizados.');
          } catch (error) {
            debugPrint('⚠️ Error sincronizando catálogos: $error');
          }
        }
        return;
      }

      // Mismo día: verificar si ya hay productos en LocalDb
      try {
        final localDb = LocalDb(); // ✅ Ahora LocalDb está importado
        final productos = await localDb.getAllProducts();
        debugPrint('📦 Productos LocalDb: ${productos.length}');

        if (productos.isEmpty && _networkMonitor.isOnline) {
          try {
            await SyncService().syncCatalogs();
          } catch (error) {
            debugPrint('⚠️ Error descargando catálogo: $error');
          }
        }
      } catch (error) {
        debugPrint('❌ Error leyendo LocalDb: $error');
        if (_networkMonitor.isOnline) {
          try {
            await SyncService().syncCatalogs();
          } catch (syncError) {
            debugPrint('❌ Error en sincronización: $syncError');
          }
        }
      }
    } catch (error, stackTrace) {
      debugPrint('❌ Error en _bootstrapBusinessDay: $error');
      debugPrint('$stackTrace');
    }
  }

  // ============================================================
  // SINCRONIZACIÓN AUTOMÁTICA
  // ============================================================

  Future<void> _startAutomaticSync() async {
    if (!mounted) return;

    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;
      if (companyId == 0 || userId == 0) {
        debugPrint('⚠️ No se inicia sincronización automática.');
        return;
      }

      await _automaticSyncService.start(
        syncAction: () async {
          if (!mounted) return;
          try {
            await SyncService().syncPendingSales(
              companyId: companyId,
              userId: userId,
              businessDate: DateTime.now(),
            );
            if (mounted) setState(() {});
          } catch (error) {
            debugPrint('❌ Error sincronizando ventas: $error');
            rethrow;
          }
        },
      );
    } catch (error) {
      debugPrint('❌ Error iniciando sincronización automática: $error');
    }
  }

  // ============================================================
  // SINCRONIZACIÓN MANUAL (botón)
  // ============================================================

  Future<void> _forceSync() async {
    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;
      if (companyId == 0 || userId == 0) {
        throw Exception('Empresa o usuario no configurado.');
      }

      await SyncService().syncCatalogs();
      if (!mounted) return;

      await SyncService().syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: DateTime.now(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronización completada.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $error', maxLines: 3, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error de inicialización',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _initError = null;
                      _initialized = false;
                    });
                    await _initialize();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final connectionStatus = _networkMonitor.status;
    final statusColor = switch (connectionStatus) {
      AppConnectionStatus.online => Colors.green,
      AppConnectionStatus.syncing => Colors.orange,
      AppConnectionStatus.offline => Colors.red,
      AppConnectionStatus.limited => Colors.amber,
    };
    final statusLabel = switch (connectionStatus) {
      AppConnectionStatus.online => 'online',
      AppConnectionStatus.syncing => 'syncing',
      AppConnectionStatus.offline => 'offline',
      AppConnectionStatus.limited => 'limited',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Punto de venta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sincronizar',
            onPressed: _forceSync,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: CircleAvatar(
                radius: 6,
                backgroundColor: statusColor,
              ),
              label: Text(statusLabel.toUpperCase()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Venta',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Estadísticas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Admin',
          ),
        ],
      ),
    );
  }
}