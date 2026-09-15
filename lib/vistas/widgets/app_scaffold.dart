import 'package:flutter/material.dart';

/// Scaffold reutilizable con `AppBar` que respeta el tema dinámico.
///
/// Uso:
///
/// ```dart
/// AppScaffold(
///   title: 'Estadísticas',
///   actions: [IconButton(...)],
///   tabs: [
///     AppTabData(label: 'Día', icon: Icons.today_outlined),
///     AppTabData(label: 'Mes', icon: Icons.calendar_month_outlined),
///   ],
///   tabController: _tabController,
///   tabView: TabBarView(controller: _tabController, children: [...]),
/// )
/// ```
///
/// - Si `tabs` es `null`, no se muestra `TabBar`.
/// - Si `tabView` es `null`, se muestra `body`.
/// - Si `tabView` no es `null`, se muestra `tabView` (para `TabBarView`).
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.tabs,
    this.tabController,
    this.tabView,
    this.body,
    this.floatingActionButton,
    this.drawer,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight = 48,
    this.tabBarHeight = 40,
  }) : assert(
          tabView != null || body != null,
          'Debe proveer `tabView` o `body`.',
        );

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final List<AppTabData>? tabs;
  final TabController? tabController;
  final Widget? tabView;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool automaticallyImplyLeading;

  /// Altura del `AppBar`. Por defecto 48 (era 56).
  final double toolbarHeight;

  /// Altura del `TabBar`. Por defecto 40.
  final double tabBarHeight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      drawer: drawer,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(
        automaticallyImplyLeading: automaticallyImplyLeading,
        leading: leading,
        toolbarHeight: toolbarHeight,
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: actions,
        bottom: (tabs != null && tabs!.isNotEmpty)
            ? PreferredSize(
                preferredSize: Size.fromHeight(tabBarHeight),
                child: TabBar(
                  controller: tabController,
                  labelColor: colors.onPrimary,
                  unselectedLabelColor:
                      colors.onPrimary.withValues(alpha: 0.7),
                  indicatorColor: colors.onPrimary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: tabs!
                      .map(
                        (t) => Tab(
                          icon: t.icon != null
                              ? Icon(t.icon, size: 16)
                              : null,
                          text: t.label,
                          height: tabBarHeight,
                        ),
                      )
                      .toList(),
                ),
              )
            : null,
      ),
      body: tabView ?? body,
    );
  }
}

/// Configuración de un tab.
class AppTabData {
  const AppTabData({
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;
}