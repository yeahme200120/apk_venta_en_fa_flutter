import 'package:flutter/material.dart';

import 'pos/pos_screen.dart';
import 'daily_stats/daily_stats_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
  });

  @override
  State<HomeShell> createState() =>
      _HomeShellState();
}

class _HomeShellState
    extends State<HomeShell> {
  final GlobalKey<PosScreenState> _posKey =
      GlobalKey<PosScreenState>();

  int _currentIndex = 0;

  int _cartCount = 0;

  @override
  Widget build(BuildContext context) {
    final colors =
        Theme.of(context).colorScheme;

    final pages = <Widget>[
      PosScreen(
        key: _posKey,
        onCartChanged: (count) {
          if (!mounted) {
            return;
          }

          if (_cartCount == count) {
            return;
          }

          setState(() {
            _cartCount = count;
          });
        },
      ),

      const DailyStatsScreen(),

      const SettingsScreen(),
    ];

    return Scaffold(
      backgroundColor: colors.surface,

      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),

      floatingActionButton:
          _currentIndex == 0
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final posState =
                        _posKey.currentState;

                    if (posState == null) {
                      return;
                    }

                    await posState.openCart(
                      context,
                    );
                  },
                  icon: Badge(
                    isLabelVisible:
                        _cartCount > 0,
                    label: Text(
                      '$_cartCount',
                    ),
                    child: const Icon(
                      Icons
                          .shopping_cart_outlined,
                    ),
                  ),
                  label: const Text(
                    'Carrito',
                  ),
                )
              : null,

      bottomNavigationBar:
          NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected:
            (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons
                  .point_of_sale_outlined,
            ),
            selectedIcon: Icon(
              Icons.point_of_sale,
            ),
            label: 'Venta',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.analytics_outlined,
            ),
            selectedIcon: Icon(
              Icons.analytics,
            ),
            label: 'Estadísticas',
          ),
          NavigationDestination(
            icon: Icon(
              Icons
                  .admin_panel_settings_outlined,
            ),
            selectedIcon: Icon(
              Icons
                  .admin_panel_settings,
            ),
            label: 'Admin',
          ),
        ],
      ),
    );
  }
}