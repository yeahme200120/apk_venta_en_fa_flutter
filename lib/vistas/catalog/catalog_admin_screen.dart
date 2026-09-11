import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/network/api_client.dart';
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
  bool _isSyncing = false;

  List<Map<String, dynamic>> _items = [];
  int _loadGeneration = 0;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ============================================================
  // CATÁLOGOS DISPONIBLES
  // ============================================================

  static const List<_CatalogInfo> _catalogs = [
    _CatalogInfo(
      title: 'Categorías',
      icon: Icons.category_outlined,
      color: Color(0xFFE91E63),
    ),
    _CatalogInfo(
      title: 'Productos',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF9AC53B),
    ),
    _CatalogInfo(
      title: 'Formas de pago',
      icon: Icons.payments_outlined,
      color: Color(0xFF4CAF50),
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
      default:
        return 'categories';
    }
  }

  bool get _isProduct => _selectedCatalog == 1;

  bool get _isPaymentMethod => _selectedCatalog == 2;

  _CatalogInfo get _currentCatalog => _catalogs[_selectedCatalog];

  // ============================================================
  // FILTRO DE BÚSQUEDA
  // ============================================================

  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;

    final q = _searchQuery.toLowerCase();

    return _items.where((item) {
      final name = (item['name'] ?? item['nombre'] ?? '')
          .toString()
          .toLowerCase();

      final code = (item['code'] ?? '').toString().toLowerCase();

      final email = (item['email'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          code.contains(q) ||
          email.contains(q);
    }).toList();
  }

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
    _searchCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // CARGA
  // ============================================================

  Future<void> _load() async {
    if (_isDisposed || !mounted) return;

    final generation = ++_loadGeneration;
    final catalogIndex = _selectedCatalog;

    _safeSetState(() {
      _loading = true;
    });

    try {
      List<Map<String, dynamic>> data;

      if (catalogIndex == 1) {
        data = await _db.getAllProducts();
      } else {
        data = await _db.getCatalogItems(
          _currentTable,
          activeOnly: false,
        );
      }

      if (_isDisposed || !mounted) return;
      if (generation != _loadGeneration) return;
      if (catalogIndex != _selectedCatalog) return;

      _safeSetState(() {
        _items = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

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

  // ============================================================
  // CAMBIO DE CATÁLOGO
  // ============================================================

  void _changeCatalog(int index) {
    if (_isDisposed || !mounted) return;
    if (index < 0 || index >= _catalogs.length) return;
    if (index == _selectedCatalog) return;

    _loadGeneration++;

    _safeSetState(() {
      _selectedCatalog = index;
      _items = [];
      _loading = true;
      _searchQuery = '';
      _searchCtrl.clear();
    });

    _load();
  }

  // ============================================================
  // EDITAR
  // ============================================================

  Future<void> _openEditor([
    Map<String, dynamic>? item,
  ]) async {
    if (_isDisposed || !mounted) return;

    if (_isPaymentMethod) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogEditScreen(
          table: _currentTable,
          isProduct: _isProduct,
          isClient: false,
          catalogTitle: _currentCatalog.title,
          item: item,
        ),
      ),
    );

    if (_isDisposed || !mounted) return;

    if (result == true) {
      await _load();

      if (!_isProduct) {
        LocalDb.notifySalesChanged();
      }
    }
  }

  // ============================================================
  // ESTADO FORMAS DE PAGO
  // ============================================================

  Future<void> _toggleStatus(
    Map<String, dynamic> item,
  ) async {
    if (_isDisposed || !mounted) return;

    final id = _toIntOrNull(item['id']);

    if (id == null) {
      _showError('ID inválido');
      return;
    }

    final currentActive = _isActive(
      item['is_active'] ??
          item['active'] ??
          item['activo'] ??
          1,
    );

    final newActive = !currentActive;

    if (_isPaymentMethod && !newActive) {
      final activeCount = _items
          .where(
            (i) => _isActive(
              i['is_active'] ??
                  i['active'] ??
                  i['activo'] ??
                  1,
            ),
          )
          .length;

      if (activeCount <= 1) {
        _showError(
          'Debes tener al menos una forma de pago activa.',
        );
        return;
      }
    }

    try {
      await _db.updateCatalogItem(
        table: _currentTable,
        id: id,
        name: item['name']?.toString() ??
            item['nombre']?.toString() ??
            '',
        code: item['code']?.toString() ?? '',
        rate: double.tryParse(
          item['rate']?.toString() ?? '',
        ),
        active: newActive,
      );

      if (_isDisposed || !mounted) return;

      await _load();
    } catch (e) {
      if (_isDisposed || !mounted) return;

      _showError(
        'Error al cambiar estado: $e',
      );
    }
  }

  // ============================================================
  // ELIMINAR / DESACTIVAR
  // ============================================================

  Future<void> _delete(
    Map<String, dynamic> item,
  ) async {
    if (_isDisposed || !mounted) return;

    if (_isPaymentMethod) return;

    final name =
        item['name']?.toString() ??
        item['nombre']?.toString() ??
        'registro';

    final id = _toIntOrNull(item['id']);

    if (id == null) {
      _showError('ID inválido');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Desactivar registro',
        ),
        content: Text(
          '¿Deseas desactivar "$name"?',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(false);
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );

    if (_isDisposed ||
        !mounted ||
        confirmed != true) {
      return;
    }

    try {
      if (_isProduct) {
        await _db.deleteProduct(id);
      } else {
        await _db.deleteCatalogItem(
          _currentTable,
          id,
        );
      }

      if (_isDisposed || !mounted) return;

      await _load();

      LocalDb.notifySalesChanged();
    } catch (e) {
      if (_isDisposed || !mounted) return;

      _showError(
        'Error al desactivar "$name": $e',
      );
    }
  }

  // ============================================================
  // SINCRONIZAR CATÁLOGOS
  // ============================================================

  Future<void> _syncCatalogs() async {
    if (_isDisposed ||
        !mounted ||
        _isSyncing) {
      return;
    }

    _safeSetState(() {
      _isSyncing = true;
    });

    try {
      final apiClient = ApiClient();

      final response = await apiClient.getCatalog();

      await _db.syncCatalogs(response);

      if (_isDisposed || !mounted) return;

      await _load();

      if (_isDisposed || !mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Catálogos sincronizados correctamente.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (_isDisposed || !mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Error al sincronizar: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (!_isDisposed && mounted) {
        _safeSetState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  int? _toIntOrNull(dynamic value) {
    if (value == null) return null;

    if (value is int) return value;

    if (value is num) {
      return value.toInt();
    }

    final text = value.toString().trim();

    if (text.isEmpty) return null;

    return int.tryParse(text);
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString().trim() ?? '',
        ) ??
        0;
  }

  bool _isActive(dynamic value) {
    if (value is bool) return value;

    if (value is num) {
      return value != 0;
    }

    final text =
        value?.toString().trim().toLowerCase();

    return text == '1' ||
        text == 'true' ||
        text == 'activo' ||
        text == 'active';
  }

  dynamic _jsonValue(
    Map<String, dynamic> item,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (item[key] != null) {
        return item[key];
      }
    }

    final raw = item['data_json'];

    if (raw is String &&
        raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map) {
          for (final key in keys) {
            if (decoded[key] != null) {
              return decoded[key];
            }
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
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final catalog = _currentCatalog;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Catálogos de la empresa',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(
              right: 8,
            ),
            child: _isSyncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Sincronizar catálogos',
                    onPressed: _syncCatalogs,
                    icon: const Icon(
                      Icons.sync,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final isDesktop = width >= 1100;

            final isTablet =
                width >= 700 && width < 1100;

            return Column(
              children: [
                // ==================================================
                // SELECTOR
                // ==================================================

                _buildCatalogSelector(
                  isDesktop: isDesktop,
                  isTablet: isTablet,
                ),

                const Divider(height: 1),

                // ==================================================
                // BÚSQUEDA
                // ==================================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    10,
                    12,
                    6,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText:
                          'Buscar en ${catalog.title.toLowerCase()}...',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                      suffixIcon:
                          _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _safeSetState(() {
                                      _searchCtrl.clear();
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                      filled: true,
                      fillColor:
                          cs.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                        borderSide:
                            BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                        vertical: 10,
                      ),
                    ),
                    onChanged: (value) {
                      _safeSetState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),

                // ==================================================
                // CONTENIDO
                // ==================================================

                Expanded(
                  child: _loading
                      ? const Center(
                          child:
                              CircularProgressIndicator(),
                        )
                      : _filteredItems.isEmpty
                          ? _buildEmptyState(catalog)
                          : width >= 800
                              ? RefreshIndicator(
                                  onRefresh: _load,
                                  child:
                                      _buildGrid(width),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child:
                                      _buildList(),
                                ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton:
          _buildFAB(catalog),
    );
  }

  // ============================================================
  // SELECTOR DE CATÁLOGOS
  // ============================================================

  Widget _buildCatalogSelector({
    required bool isDesktop,
    required bool isTablet,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final isSmallMobile = width < 360;
        final isMobile = width < 700;

        final double cardWidth;
        final double selectorHeight;
        final double horizontalPadding;
        final double iconSize;
        final double fontSize;

        if (isSmallMobile) {
          cardWidth = 96;
          selectorHeight = 88;
          horizontalPadding = 8;
          iconSize = 21;
          fontSize = 11;
        } else if (isMobile) {
          cardWidth = 108;
          selectorHeight = 92;
          horizontalPadding = 10;
          iconSize = 22;
          fontSize = 12;
        } else if (isTablet) {
          cardWidth = 118;
          selectorHeight = 98;
          horizontalPadding = 16;
          iconSize = 23;
          fontSize = 12;
        } else {
          cardWidth = 128;
          selectorHeight = 104;
          horizontalPadding = 20;
          iconSize = 24;
          fontSize = 13;
        }

        return SizedBox(
          width: double.infinity,
          height: selectorHeight,
          child: ScrollConfiguration(
            behavior:
                const ScrollBehavior().copyWith(
              scrollbars: false,
              overscroll: false,
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics:
                  const BouncingScrollPhysics(
                parent:
                    AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 8,
              ),
              itemCount: _catalogs.length,
              separatorBuilder: (_, __) {
                return const SizedBox(
                  width: 8,
                );
              },
              itemBuilder: (
                context,
                index,
              ) {
                final catalog =
                    _catalogs[index];

                final selected =
                    index == _selectedCatalog;

                return SizedBox(
                  width: cardWidth,
                  height: selectorHeight - 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(14),
                      onTap: () {
                        if (_selectedCatalog ==
                            index) {
                          return;
                        }

                        _changeCatalog(index);
                      },
                      child: AnimatedContainer(
                        duration:
                            const Duration(
                          milliseconds: 180,
                        ),
                        curve: Curves.easeOut,
                        width: cardWidth,
                        height:
                            selectorHeight - 16,
                        padding:
                            EdgeInsets.symmetric(
                          horizontal:
                              isSmallMobile
                                  ? 6
                                  : 8,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? catalog.color
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(
                            14,
                          ),
                          border: Border.all(
                            color: selected
                                ? catalog.color
                                : Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(
                                      alpha: .35,
                                    ),
                            width:
                                selected ? 1.5 : 1,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: catalog
                                        .color
                                        .withValues(
                                      alpha: .18,
                                    ),
                                    blurRadius: 8,
                                    offset:
                                        const Offset(
                                      0,
                                      2,
                                    ),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              catalog.icon,
                              size: iconSize,
                              color: selected
                                  ? Colors.white
                                  : catalog.color,
                            ),
                            const SizedBox(
                              height: 5,
                            ),
                            Flexible(
                              child: Padding(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 2,
                                ),
                                child: Text(
                                  catalog.title,
                                  textAlign:
                                      TextAlign
                                          .center,
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        fontSize,
                                    height: 1.1,
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                    color: selected
                                        ? Colors.white
                                        : Theme.of(
                                            context,
                                          )
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
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // LISTA
  // ============================================================

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredItems.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildItemCard(
        _filteredItems[i],
        compact: true,
      ),
    );
  }

  // ============================================================
  // GRID
  // ============================================================

  Widget _buildGrid(double width) {
    final cols = width >= 1400
        ? 4
        : width >= 1050
            ? 3
            : 2;

    return GridView.builder(
      padding: EdgeInsets.all(
        width >= 1200 ? 24 : 16,
      ),
      gridDelegate:
          SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: 155,
      ),
      itemCount: _filteredItems.length,
      itemBuilder: (_, i) => _buildItemCard(
        _filteredItems[i],
        compact: false,
      ),
    );
  }

  // ============================================================
  // TARJETA
  // ============================================================

  Widget _buildItemCard(
    Map<String, dynamic> item, {
    required bool compact,
  }) {
    final catalog = _currentCatalog;

    final name =
        item['name']?.toString() ??
        item['nombre']?.toString() ??
        'Sin nombre';

    final code =
        item['code']?.toString() ?? '';

    final active = _isActive(
      item['is_active'] ??
          item['active'] ??
          item['activo'] ??
          1,
    );

    final details =
        _buildDetails(item, code);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.center,
          children: [
            _buildIconBox(
              catalog,
              size: compact ? 46 : 44,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight:
                          FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      details,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _buildStatusBadge(active),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (_isPaymentMethod)
              _buildToggleSwitch(
                item,
                active,
              )
            else
              _buildActions(
                item,
                active,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SWITCH FORMAS DE PAGO
  // ============================================================

  Widget _buildToggleSwitch(
    Map<String, dynamic> item,
    bool active,
  ) {
    return Switch(
      value: active,
      onChanged: (_) =>
          _toggleStatus(item),
      activeThumbColor: Colors.green,
      inactiveThumbColor: Colors.grey,
    );
  }

  // ============================================================
  // DETALLES
  // ============================================================

  String _buildDetails(
    Map<String, dynamic> item,
    String code,
  ) {
    if (_isProduct) {
      final price =
          _toDouble(item['price']);

      final stock =
          _toDouble(item['stock']);

      final parts = <String>[];

      if (code.isNotEmpty) {
        parts.add(code);
      }

      final categoryName = _jsonValue(
        item,
        [
          'categoria_nombre',
          'category_name',
        ],
      );

      if (categoryName != null &&
          categoryName
              .toString()
              .trim()
              .isNotEmpty) {
        parts.add(
          'Cat: ${categoryName.toString()}',
        );
      }

      parts.add(
        'Stock: ${stock.toStringAsFixed(0)}',
      );

      parts.add(
        '\$${price.toStringAsFixed(2)}',
      );

      return parts.join('  •  ');
    }

    return code;
  }

  // ============================================================
  // ICONO
  // ============================================================

  Widget _buildIconBox(
    _CatalogInfo catalog, {
    double size = 48,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: catalog.color.withValues(
            alpha: 0.12,
          ),
          borderRadius:
              BorderRadius.circular(
            size >= 48 ? 14 : 12,
          ),
        ),
        child: Icon(
          catalog.icon,
          color: catalog.color,
          size: size >= 48 ? 24 : 22,
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO
  // ============================================================

  Widget _buildStatusBadge(bool active) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: active
            ? Colors.green.withValues(
                alpha: 0.10,
              )
            : Colors.grey.withValues(
                alpha: 0.12,
              ),
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            active
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            size: 15,
            color: active
                ? Colors.green
                : Colors.grey.shade600,
          ),
          const SizedBox(width: 5),
          Text(
            active
                ? 'Activo'
                : 'Inactivo',
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  FontWeight.w600,
              color: active
                  ? Colors.green
                  : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACCIONES
  // ============================================================

  Widget _buildActions(
    Map<String, dynamic> item,
    bool active, {
    required bool compact,
  }) {
    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        IconButton(
          visualDensity:
              VisualDensity.compact,
          onPressed: () =>
              _openEditor(item),
          icon: const Icon(
            Icons.edit_outlined,
            size: 21,
          ),
        ),
        IconButton(
          visualDensity:
              VisualDensity.compact,
          onPressed: active
              ? () => _delete(item)
              : null,
          icon: Icon(
            active
                ? Icons.delete_outline
                : Icons.check_circle_outline,
            size: 21,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ESTADO VACÍO
  // ============================================================

  Widget _buildEmptyState(
    _CatalogInfo catalog,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 24,
        ),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context)
                          .size
                          .height *
                      0.5,
            ),
            child: Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration:
                        BoxDecoration(
                      color: catalog.color
                          .withValues(
                        alpha: 0.10,
                      ),
                      shape:
                          BoxShape.circle,
                    ),
                    child: Icon(
                      catalog.icon,
                      size: 46,
                      color: catalog.color
                          .withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'Sin resultados para "$_searchQuery"'
                        : 'No hay registros',
                    textAlign:
                        TextAlign.center,
                    style:
                        const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 420,
                    ),
                    child: Text(
                      _searchQuery.isNotEmpty
                          ? 'Intenta con otro término de búsqueda.'
                          : 'Todavía no existen registros en ${catalog.title.toLowerCase()}.',
                      textAlign:
                          TextAlign.center,
                      softWrap: true,
                      style: TextStyle(
                        color:
                            Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isPaymentMethod &&
                      _searchQuery.isEmpty)
                    FilledButton.icon(
                      onPressed:
                          () => _openEditor(),
                      icon: const Icon(
                        Icons.add,
                      ),
                      label:
                          const Text(
                        'Agregar',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FAB
  // ============================================================

  Widget _buildFAB(
    _CatalogInfo catalog,
  ) {
    if (_isPaymentMethod) {
      return const SizedBox.shrink();
    }

    return FloatingActionButton.extended(
      onPressed: () => _openEditor(),
      backgroundColor:
          catalog.color,
      foregroundColor:
          Colors.white,
      icon: const Icon(Icons.add),
      label: ConstrainedBox(
        constraints:
            const BoxConstraints(
          maxWidth: 180,
        ),
        child: Text(
          'Nuevo ${catalog.title}',
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
        ),
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

  const _CatalogInfo({
    required this.title,
    required this.icon,
    required this.color,
  });
}