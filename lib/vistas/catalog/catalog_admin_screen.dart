import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/database/local_db.dart';
import 'catalog_edit_screen.dart';

class CatalogAdminScreen extends StatefulWidget {
  const CatalogAdminScreen({super.key});

  @override
  State<CatalogAdminScreen> createState() => _CatalogAdminScreenState();
}

class _CatalogAdminScreenState extends State<CatalogAdminScreen> {
  final LocalDb _db = LocalDb();

  int _selectedCatalog = 0;
  bool _loading = true;
  bool _isDisposed = false;

  List<Map<String, dynamic>> _items = [];
  int _loadGeneration = 0;

  // ============================================================
  // CATÃLOGOS
  //
  // Los primeros 3 estÃ¡n habilitados (v1 bÃ¡sica).
  // El resto se muestran como "PrÃ³ximamente" y estÃ¡n deshabilitados.
  // ============================================================

  static const List<_CatalogInfo> _catalogs = [
    _CatalogInfo(
      title: 'CategorÃ­as',
      icon: Icons.category_outlined,
      color: Color(0xFFE91E63),
      enabled: true,
    ),
    _CatalogInfo(
      title: 'Productos',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF9AC53B),
      enabled: true,
    ),
    _CatalogInfo(
      title: 'Formas de pago',
      icon: Icons.payments_outlined,
      color: Color(0xFF4CAF50),
      enabled: true,
    ),
    _CatalogInfo(
      title: 'Clientes',
      icon: Icons.people_outline,
      color: Color(0xFF2196F3),
      enabled: false,
    ),
    _CatalogInfo(
      title: 'Impuestos',
      icon: Icons.percent_outlined,
      color: Color(0xFFFF9800),
      enabled: false,
    ),
    _CatalogInfo(
      title: 'Unidades',
      icon: Icons.straighten_outlined,
      color: Color(0xFF673AB7),
      enabled: false,
    ),
    _CatalogInfo(
      title: 'Promociones',
      icon: Icons.local_offer_outlined,
      color: Color(0xFF00A896),
      enabled: false,
    ),
    _CatalogInfo(
      title: 'Cupones',
      icon: Icons.confirmation_number_outlined,
      color: Color(0xFF795548),
      enabled: false,
    ),
  ];

  String get _currentTable {
    switch (_selectedCatalog) {
      case 0:
        return 'categories';
      case 1:
        return 'products';
      case 2:
        return 'payment_methods';
      case 3:
        return 'clients';
      case 4:
        return 'taxes';
      case 5:
        return 'units';
      case 6:
        return 'promotions';
      case 7:
        return 'coupons';
      default:
        return 'categories';
    }
  }

  bool get _isProduct => _selectedCatalog == 1;
  bool get _isClient => _selectedCatalog == 3;

  // Formas de pago: Ã­ndice 2 en el nuevo orden
  bool get _isPaymentMethod => _selectedCatalog == 2;

  _CatalogInfo get _currentCatalog => _catalogs[_selectedCatalog];

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      _load();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  // ============================================================
  // CARGA
  // ============================================================

  Future<void> _load() async {
    if (_isDisposed || !mounted) return;
    final generation = ++_loadGeneration;
    final catalogIndex = _selectedCatalog;

    _safeSetState(() => _loading = true);

    try {
      List<Map<String, dynamic>> data;

      if (catalogIndex == 1) {
        data = await _db.getAllProducts();
      } else if (catalogIndex == 3) {
        data = await _db.getAllClients();
      } else {
        data = await _db.getCatalogItems(_currentTable, activeOnly: false);
      }

      if (_isDisposed || !mounted) return;
      if (generation != _loadGeneration) return;
      if (catalogIndex != _selectedCatalog) return;

      _safeSetState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (_isDisposed || !mounted) return;
      if (generation != _loadGeneration) return;

      _safeSetState(() {
        _items = [];
        _loading = false;
      });
      _showError('Error al cargar: $e');
    }
  }

  void _changeCatalog(int index) {
    if (_isDisposed || !mounted) return;
    // Bloquear catÃ¡logos deshabilitados
    if (!_catalogs[index].enabled) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Esta secciÃ³n estarÃ¡ disponible en una prÃ³xima versiÃ³n.'),
          duration: Duration(seconds: 2),
        ));
      return;
    }
    if (index == _selectedCatalog) return;

    _loadGeneration++;
    _safeSetState(() {
      _selectedCatalog = index;
      _items = [];
      _loading = true;
    });
    _load();
  }

  // ============================================================
  // EDITAR
  // ============================================================

  Future<void> _openEditor([Map<String, dynamic>? item]) async {
    if (_isDisposed || !mounted) return;
    if (_isPaymentMethod) return;

    final table = _currentTable;
    final isProduct = _isProduct;
    final isClient = _isClient;
    final catalogTitle = _currentCatalog.title;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogEditScreen(
          table: table,
          isProduct: isProduct,
          isClient: isClient,
          catalogTitle: catalogTitle,
          item: item,
        ),
      ),
    );

    if (_isDisposed || !mounted) return;
    if (result == true) {
      await _load();
      // El CatalogEditScreen ya llama a LocalDb.notifySalesChanged() para productos.
      // Para categorÃ­as y otros catÃ¡logos tambiÃ©n recargamos el catÃ¡logo en POS.
      if (!_isProduct) LocalDb.notifySalesChanged();
    }
  }

  // ============================================================
  // TOGGLE ACTIVO (formas de pago usan switch)
  // ============================================================

  Future<void> _toggleStatus(Map<String, dynamic> item) async {
    if (_isDisposed || !mounted) return;
    final id = _toIntOrNull(item['id']);
    if (id == null) { _showError('ID invÃ¡lido'); return; }

    final currentActive = _isActive(item['is_active'] ?? item['active'] ?? item['activo'] ?? 1);
    final newActive = !currentActive;

    // Validar que quede al menos una forma de pago activa
    if (_isPaymentMethod && !newActive) {
      final activeCount = _items.where((i) {
        return _isActive(i['is_active'] ?? i['active'] ?? i['activo'] ?? 1);
      }).length;
      if (activeCount <= 1) {
        _showError('Debes tener al menos una forma de pago activa.');
        return;
      }
    }

    try {
      await _db.updateCatalogItem(
        table: _currentTable,
        id: id,
        name: item['name']?.toString() ?? item['nombre']?.toString() ?? '',
        code: item['code']?.toString() ?? '',
        rate: double.tryParse(item['rate']?.toString() ?? ''),
        active: newActive,
      );
      if (_isDisposed || !mounted) return;
      await _load();
    } catch (e) {
      if (_isDisposed || !mounted) return;
      _showError('Error al cambiar estado: $e');
    }
  }

  // ============================================================
  // ELIMINAR (desactivar)
  // ============================================================

  Future<void> _delete(Map<String, dynamic> item) async {
    if (_isDisposed || !mounted) return;
    if (_isPaymentMethod) return;

    final name = item['name']?.toString() ?? item['nombre']?.toString() ?? 'registro';
    final id = _toIntOrNull(item['id']);
    if (id == null) { _showError('ID invÃ¡lido'); return; }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar registro'),
        content: Text('Â¿Deseas desactivar "$name"?',
            maxLines: 4, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (_isDisposed || !mounted || confirmed != true) return;

    try {
      if (_isProduct) {
        await _db.deleteProduct(id);
      } else if (_isClient) {
        await _db.deleteClient(id);
      } else {
        await _db.deleteCatalogItem(_currentTable, id);
      }
      if (_isDisposed || !mounted) return;
      await _load();
      LocalDb.notifySalesChanged();
    } catch (e) {
      if (_isDisposed || !mounted) return;
      _showError('Error al desactivar "$name": $e');
    }
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final t = v.toString().trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  double _toDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse(v?.toString().trim() ?? '') ?? 0;

  bool _isActive(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final t = v?.toString().trim().toLowerCase();
    return t == '1' || t == 'true' || t == 'activo' || t == 'active';
  }

  dynamic _jsonValue(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      if (item[key] != null) return item[key];
    }
    final raw = item['data_json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final key in keys) {
            if (decoded[key] != null) return decoded[key];
          }
        }
      } catch (_) {}
    }
    return null;
  }

  void _showError(String msg) {
    if (_isDisposed || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, maxLines: 4, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final catalog = _currentCatalog;

    return Scaffold(
      appBar: AppBar(title: const Text('CatÃ¡logos de la empresa')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isDesktop = width >= 1100;
            final isTablet = width >= 700 && width < 1100;

            return Column(
              children: [
                _buildCatalogSelector(isDesktop, isTablet),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _items.isEmpty
                          ? _buildEmptyState(catalog)
                          : width >= 800
                              ? RefreshIndicator(onRefresh: _load, child: _buildGrid(width))
                              : RefreshIndicator(onRefresh: _load, child: _buildList()),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _buildFAB(catalog),
    );
  }

  // ============================================================
  // SELECTOR DE CATÃLOGOS
  // ============================================================

  Widget _buildCatalogSelector(bool isDesktop, bool isTablet) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 20 : isTablet ? 16 : 10,
          vertical: 8,
        ),
        itemCount: _catalogs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final catalog = _catalogs[index];
          final selected = index == _selectedCatalog;
          final enabled = catalog.enabled;
          final width = isDesktop ? 128.0 : isTablet ? 118.0 : 108.0;

          return SizedBox(
            width: width,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.45,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _changeCatalog(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? catalog.color
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? catalog.color
                            : Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.35),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(catalog.icon,
                            size: isDesktop ? 24 : 22,
                            color: selected
                                ? Colors.white
                                : catalog.color),
                        const SizedBox(height: 5),
                        Expanded(
                          child: Center(
                            child: Text(
                              // Agregar "PrÃ³x." a catÃ¡logos deshabilitados
                              enabled
                                  ? catalog.title
                                  : '${catalog.title}\n(PrÃ³x.)',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isDesktop ? 12 : 11,
                                height: 1.1,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // LISTA / GRID DE ÃTEMS
  // ============================================================

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildItemCard(_items[i], compact: true),
    );
  }

  Widget _buildGrid(double width) {
    final cols = width >= 1400 ? 4 : width >= 1050 ? 3 : 2;
    return GridView.builder(
      padding: EdgeInsets.all(width >= 1200 ? 24 : 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 155,
      ),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildItemCard(_items[i], compact: false),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, {required bool compact}) {
    final catalog = _currentCatalog;
    final name = item['name']?.toString() ??
        item['nombre']?.toString() ??
        'Sin nombre';
    final code = item['code']?.toString() ?? '';
    final active = _isActive(
        item['is_active'] ?? item['active'] ?? item['activo'] ?? 1);
    final details = _buildDetails(item, code);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildIconBox(catalog, size: compact ? 46 : 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  _buildStatusBadge(active),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Formas de pago: switch; el resto: botones editar/desactivar
            if (_isPaymentMethod)
              _buildToggleSwitch(item, active)
            else
              _buildActions(item, active, compact: compact),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleSwitch(Map<String, dynamic> item, bool active) {
    return Switch(
      value: active,
      onChanged: (_) => _toggleStatus(item),
      activeThumbColor: Colors.green,
      inactiveThumbColor: Colors.grey,
    );
  }

  String _buildDetails(Map<String, dynamic> item, String code) {
    if (_isProduct) {
      final price = _toDouble(item['price']);
      final stock = _toDouble(item['stock']);
      final parts = <String>[];
      if (code.isNotEmpty) parts.add(code);
      final categoryName = _jsonValue(
          item, ['categoria_nombre', 'category_name']);
      if (categoryName != null && categoryName.toString().trim().isNotEmpty) {
        parts.add('Cat: ${categoryName.toString()}');
      }
      parts.add('Stock: ${stock.toStringAsFixed(0)}');
      parts.add('\$${price.toStringAsFixed(2)}');
      return parts.join('  â€¢  ');
    }
    if (_isClient) {
      final parts = <String>[];
      final phone = item['phone']?.toString().trim();
      final email = item['email']?.toString().trim();
      final rfc = item['rfc']?.toString().trim();
      if (phone != null && phone.isNotEmpty) parts.add(phone);
      if (email != null && email.isNotEmpty) parts.add(email);
      if (rfc != null && rfc.isNotEmpty) parts.add('RFC: $rfc');
      return parts.join('  â€¢  ');
    }
    if (_selectedCatalog == 4) {
      final rate = _toDouble(item['rate']);
      final parts = <String>[];
      if (code.isNotEmpty) parts.add(code);
      parts.add('Tasa: ${rate.toStringAsFixed(2)}%');
      return parts.join('  â€¢  ');
    }
    return code;
  }

  Widget _buildIconBox(_CatalogInfo catalog, {double size = 48}) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: catalog.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size >= 48 ? 14 : 12),
        ),
        child: Icon(catalog.icon,
            color: catalog.color, size: size >= 48 ? 24 : 22),
      ),
    );
  }

  Widget _buildStatusBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? Colors.green.withValues(alpha: 0.10)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 15,
            color: active ? Colors.green : Colors.grey.shade600,
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Activo' : 'Inactivo',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.green : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> item, bool active,
      {required bool compact}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => _openEditor(item),
          icon: const Icon(Icons.edit_outlined, size: 21),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: active ? () => _delete(item) : null,
          icon: Icon(
            active ? Icons.delete_outline : Icons.check_circle_outline,
            size: 21,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(_CatalogInfo catalog) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: catalog.color.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(catalog.icon,
                        size: 46, color: catalog.color.withOpacity(.55)),
                  ),
                  const SizedBox(height: 18),
                  const Text('No hay registros',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      'TodavÃ­a no existen registros en ${catalog.title.toLowerCase()}.',
                      textAlign: TextAlign.center,
                      softWrap: true,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isPaymentMethod)
                    FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB(_CatalogInfo catalog) {
    if (_isPaymentMethod) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: () => _openEditor(),
      backgroundColor: catalog.color,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text('Nuevo ${catalog.title}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

// ============================================================
// MODELO VISUAL
// ============================================================

class _CatalogInfo {
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _CatalogInfo({
    required this.title,
    required this.icon,
    required this.color,
    this.enabled = true,
  });
}


