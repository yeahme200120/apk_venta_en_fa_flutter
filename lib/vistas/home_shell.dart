import 'package:flutter/material.dart';

import '../core/network/network_monitor.dart';
import '../core/services/automatic_sync_service.dart';
import '../core/services/catalog_service.dart';
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

  static final List<Widget> _pages = <Widget>[
    const PosScreen(),
    const DailyStatsScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _networkMonitor.addListener(_handleNetworkChange);
    _networkMonitor.initialize();
    _bootstrapBusinessDay();
    _startAutomaticSync();
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

  Future<void> _bootstrapBusinessDay() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;
    if (companyId == 0 || userId == 0) return;

    final today = DateTime.now();
    final lastDate = await AppStorage().getLastBusinessDate();
    final lastBusinessDate = lastDate != null ? DateTime.tryParse(lastDate) : null;

    if (lastBusinessDate == null || lastBusinessDate.day != today.day || lastBusinessDate.month != today.month || lastBusinessDate.year != today.year) {
      await DailyCleanupService().prepareNewBusinessDay(
        companyId: companyId,
        userId: userId,
        businessDate: today,
      );
      await AppStorage().saveLastBusinessDate(today);
      if (_networkMonitor.isOnline) {
        await CatalogService().downloadCatalogForToday(
          companyId: companyId,
          userId: userId,
          businessDate: today,
        );
      }
      return;
    }

    final db = await CatalogService().downloadCatalogForToday(
      companyId: companyId,
      userId: userId,
      businessDate: today,
    );

    if (db.isEmpty && _networkMonitor.isOnline) {
      await CatalogService().downloadCatalogForToday(
        companyId: companyId,
        userId: userId,
        businessDate: today,
      );
    }
  }

  Future<void> _startAutomaticSync() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;
    if (companyId == 0 || userId == 0) return;

    await _automaticSyncService.start(
      syncAction: () async {
        await SyncService().syncPendingSales(
          companyId: companyId,
          userId: userId,
          businessDate: DateTime.now(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
