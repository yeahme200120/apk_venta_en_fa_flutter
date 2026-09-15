import 'package:flutter/material.dart';

import '../caja/cash_management_screen.dart';
import '../daily_stats/daily_stats_screen.dart';
import '../pos/pos_screen.dart';

// 👇 Ajusta estos imports a tus pantallas reales:
// import '../admin/admin_screen.dart';          // tu pantalla de configuraciones
// import '../sync/sync_screen.dart';            // si la sigues usando

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          PosScreen(),               // 0 - Venta
          DailyStatsScreen(),        // 1 - Estadísticas
          CashManagementScreen(),    // 2 - Caja
          _AdminPlaceholder(),       // 3 - Admin (reemplaza con tu AdminScreen)
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Caja',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Admin',
          ),
        ],
      ),
    );
  }
}

/// Placeholder temporal. Reemplaza con tu pantalla real de admin.
class _AdminPlaceholder extends StatelessWidget {
  const _AdminPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin')),
    );
  }
}