import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/product.dart';
import '../../core/models/sale_model.dart';
import '../../core/network/api_client.dart';
import '../../core/payments/payment_breakdown.dart';
import '../../core/storage/app_storage.dart';
import '../../core/services/sync_service.dart';
import '../operacion/operation_screen.dart';
import 'cart_screen.dart';
import '../ventas/sale_detail_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    this.onCartChanged,
  });

  final ValueChanged<int>? onCartChanged;

  @override
  PosScreenState createState() => PosScreenState();
}

class PosScreenState extends State<PosScreen> {
  final LocalDb _db = LocalDb();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<CartItem>> _cartNotifier = ValueNotifier([]);

  StreamSubscription<void>? _salesChangesSubscription;
  bool _refreshing = false;
  bool _syncing = false;
  bool _refreshQueued = false;

  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId; // null = Todos
  bool _isLoading = true;

  int _todaySales = 0;
  int _pendingSales = 0;
  int _cancelledSales = 0;

  int? _pendingSaleId;

  bool _cajasActivas = false;
  bool _mesasActivas = false;
  bool _cajaAbierta = false;

  List<Map<String, dynamic>> _tables = const [];

  int? _selectedTableId;
  String? _selectedTableName;

  ValueNotifier<List<CartItem>> get cartNotifier => _cartNotifier;

  void _notifyCartChanged() {
    widget.onCartChanged?.call(_cartNotifier.value.length);
  }

  void _setCart(List<CartItem> cart) {
    _cartNotifier.value = List<CartItem>.from(cart);
    _notifyCartChanged();
  }

  @override
  void initState() {
    super.initState();

    _salesChangesSubscription = LocalDb.salesChanges.listen((_) {
      _handleSalesChanged();
    });

    _loadProducts();
    _loadOperationState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyCartChanged();
    });
  }

  @override
  void dispose() {
    _salesChangesSubscription?.cancel();
    _salesChangesSubscription = null;
    _searchController.dispose();
    _cartNotifier.dispose();
    super.dispose();
  }

  // ============================================================
  // CARGA DE DATOS
  // ============================================================

  Future<void> _loadProducts({bool showLoading = false}) async {
    if (_refreshing) return;
    _refreshing = true;

    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final items = await _db.getProducts();
      final sales = await _db.getTodaySales();
      final cats = await _db.getCategories();

      if (!mounted) return;

      setState(() {
        _products = items.map(Product.fromMap).toList();
        _categories = cats.map((c) => Map<String, dynamic>.from(c)).toList();
        _todaySales = sales.length;
        _pendingSales = sales.where((s) => s['sync_status'] != 'synced').length;
        _cancelledSales = sales.where((s) => s['status'] == 'cancelled').length;
        _isLoading = false;
      });

      // Si la categoría seleccionada ya no existe, resetear
      if (_selectedCategoryId != null) {
        final exists = _categories.any((c) => _catId(c) == _selectedCategoryId);
        if (!exists && mounted) setState(() => _selectedCategoryId = null);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible actualizar la caja: $error')),
      );
    } finally {
      _refreshing = false;
    }
  }

  int? _catId(Map<String, dynamic> c) {
    final v = c['id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _handleSalesChanged() async {
    if (!mounted) return;
    if (_refreshing || _syncing) {
      _refreshQueued = true;
      return;
    }
    await _loadProducts();
    if (!mounted || !_refreshQueued) return;
    _refreshQueued = false;
    await _loadProducts();
  }

  Future<void> _refreshAll() async {
    if (!mounted || _syncing) return;
    setState(() => _syncing = true);

    try {
      final offline = await AppStorage().isOfflineSession();
      if (!offline) {
        try {
          await SyncService().syncPull();
        } catch (error) {
          debugPrint('ℹ️ Actualización remota omitida: $error');
        }
      }
      await _loadProducts();
      await _loadOperationState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja actualizada correctamente.'), duration: Duration(seconds: 2)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No fue posible actualizar la caja: $error')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _loadOperationState() async {
    var state = await AppStorage().getOperationState();
    try {
      state = await ApiClient().getOperationStatus();
      await AppStorage().saveOperationState(state);
      if (state['mesas_activas'] == true) {
        _tables = await ApiClient().getTables();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _cajasActivas = state['cajas_activas'] == true;
      _mesasActivas = state['mesas_activas'] == true;
      _cajaAbierta = state['caja_abierta'] != null;
    });
  }

  // ============================================================
  // CARRITO
  // ============================================================

  List<Map<String, dynamic>> _currentSaleItems() {
    return _cartNotifier.value.map((item) => {
      'product_id': item.product.id,
      'name': item.product.name,
      'quantity': item.quantity,
      'unit_price': item.product.price,
      'total': item.subtotal,
    }).toList();
  }

  double get _total => _cartNotifier.value.fold(0, (sum, item) => sum + item.subtotal);

  void _addToCart(Product product) {
    final current = List<CartItem>.from(_cartNotifier.value);
    final index = current.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final existing = current[index];
      current[index] = CartItem(product: existing.product, quantity: existing.quantity + 1);
    } else {
      current.add(CartItem(product: product, quantity: 1));
    }
    _setCart(current);
  }

  void _changeQuantity(int productId, int delta) {
    final current = List<CartItem>.from(_cartNotifier.value);
    final index = current.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;
    final newQty = current[index].quantity + delta;
    if (newQty <= 0) {
      current.removeAt(index);
    } else {
      current[index] = CartItem(product: current[index].product, quantity: newQty);
    }
    _setCart(current);
  }

  void _removeFromCart(int productId) {
    final current = List<CartItem>.from(_cartNotifier.value);
    current.removeWhere((item) => item.product.id == productId);
    _setCart(current);
  }

  void _clearCart() => _setCart([]);

  // ============================================================
  // ABRIR CARRITO
  // ============================================================

  Future<void> openCart(BuildContext cartContext) async {
    if (!mounted) return;
    await Navigator.of(cartContext).push(MaterialPageRoute(
      builder: (_) => CartScreen(
        cartNotifier: _cartNotifier,
        onQuantityChanged: _changeQuantity,
        onRemove: _removeFromCart,
        onClear: _clearCart,
        onCheckout: _confirmSale,
      ),
    ));
    if (!mounted) return;
    _notifyCartChanged();
  }

  Future<void> _openCart() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CartScreen(
        cartNotifier: _cartNotifier,
        onQuantityChanged: _changeQuantity,
        onRemove: _removeFromCart,
        onClear: _clearCart,
        onCheckout: _confirmSale,
      ),
    ));
    if (mounted) setState(() {});
  }

  // ============================================================
  // GUARDAR PENDIENTE
  // ============================================================

  Future<bool> _canOperateSale() async {
    await _loadOperationState();
    if (_cajasActivas && !_cajaAbierta) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Un cajero debe abrir la caja antes de registrar o cobrar ventas.')),
        );
      }
      return false;
    }
    return true;
  }

  // ============================================================
  // CONFIRMAR VENTA
  // ============================================================

  Future<bool> _confirmSale() async {
    if (_cartNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos al carrito antes de confirmar.')),
      );
      return false;
    }
    if (!await _canOperateSale()) return false;

    final paymentData = await _showPaymentDialog();
    if (paymentData == null) return false;

    final uuid = 'sale_${DateTime.now().millisecondsSinceEpoch}';
    final saleItems = _currentSaleItems();
    final payments = (paymentData['payments'] as List<Map<String, dynamic>>?) ?? const [];

    final breakdown = PaymentBreakdown(
      total: _total,
      payments: payments.map((item) => PaymentEntry(
        method: (item['method'] ?? 'Efectivo').toString(),
        amount: (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0.0,
      )).toList(),
    );

    final cashAmount = breakdown.cashAmount;
    final change = breakdown.change;
    var saleId = _pendingSaleId;

    try {
      if (saleId != null) {
        final paid = await _db.payPendingSale(saleId, payments: payments, paymentMethod: cashAmount > 0 ? 'Efectivo' : 'Mixto', cashReceived: cashAmount, changeDue: change);
        if (!paid) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La venta pendiente ya no está disponible.')));
          return false;
        }
      } else {
        saleId = await _db.saveSale(uuid: uuid, items: saleItems, payments: payments, total: _total, status: 'paid', syncStatus: 'pending', paymentMethod: cashAmount > 0 ? 'Efectivo' : 'Mixto', cashReceived: cashAmount, changeDue: change);
      }
    } on StateError catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      return false;
    }

    final generatedSale = await _db.getSaleById(saleId);
    if (generatedSale != null && mounted) {
      final sale = generatedSale;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SaleDetailScreen(
          sale: SaleModel(
            id: int.tryParse('${sale['id'] ?? 0}') ?? 0,
            uuidLocal: sale['uuid_local']?.toString() ?? uuid,
            serverId: null,
            businessDate: DateTime.now().toIso8601String().substring(0, 10),
            total: (sale['total'] is num) ? (sale['total'] as num).toDouble() : _total,
            syncStatus: sale['sync_status']?.toString() ?? 'pending',
            status: sale['status']?.toString() ?? 'paid',
            items: saleItems.map((item) => SaleItemModel(
              id: 0, saleId: 0,
              productId: int.tryParse('${item['product_id'] ?? 0}') ?? 0,
              name: item['name']?.toString() ?? '',
              quantity: (item['quantity'] is num) ? (item['quantity'] as num).toDouble() : 0.0,
              unitPrice: (item['unit_price'] is num) ? (item['unit_price'] as num).toDouble() : 0.0,
              total: (item['total'] is num) ? (item['total'] as num).toDouble() : 0.0,
            )).toList(),
            payments: payments.map((item) => SalePaymentModel(
              id: 0, saleId: 0,
              method: item['method']?.toString() ?? '',
              amount: (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0.0,
            )).toList(),
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ),
      ));
    }

    if (!mounted) return false;
    setState(() {
      _setCart([]);
      _pendingSaleId = null;
      _selectedTableId = null;
      _selectedTableName = null;
    });
    await _loadProducts();
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Venta pagada. Cambio: \$${change.toStringAsFixed(2)}')),
    );
    return true;
  }

  // ============================================================
  // DIÁLOGO DE PAGO
  // ============================================================

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(total: _total),
    );
  }

  // ============================================================
  // OPERACIÓN
  // ============================================================

  Future<void> _openOperation() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OperationScreen()));
    await _loadOperationState();
  }

  // ============================================================
  // FILTRO POR CATEGORÍA (panel lateral)
  // ============================================================

  void _openCategoryFilter() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Filtrar por categoría', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // Opción "Todos"
                    ListTile(
                      leading: Icon(
                        Icons.all_inclusive,
                        color: _selectedCategoryId == null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: const Text('Todos'),
                      selected: _selectedCategoryId == null,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withAlpha(18),
                      onTap: () {
                        setState(() => _selectedCategoryId = null);
                        Navigator.of(sheetCtx).pop();
                      },
                    ),
                    ..._categories.map((cat) {
                      final id = _catId(cat);
                      final name = (cat['name'] ?? cat['nombre'] ?? '').toString();
                      final selected = _selectedCategoryId == id;
                      return ListTile(
                        leading: Icon(
                          Icons.label_outline,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(name),
                        selected: selected,
                        selectedTileColor: Theme.of(context).colorScheme.primary.withAlpha(18),
                        onTap: () {
                          setState(() => _selectedCategoryId = id);
                          Navigator.of(sheetCtx).pop();
                        },
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerHighest,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.point_of_sale, color: colorScheme.onPrimary),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Caja', overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _syncing ? null : _refreshAll,
            icon: _syncing
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                : const Icon(Icons.refresh),
          ),
          ValueListenableBuilder<List<CartItem>>(
            valueListenable: _cartNotifier,
            builder: (context, items, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: items.isEmpty ? 'Carrito vacío' : 'Abrir carrito',
                    onPressed: _openCart,
                    icon: const Icon(Icons.shopping_cart_outlined),
                  ),
                  if (items.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: colorScheme.error, borderRadius: BorderRadius.circular(999)),
                        child: Text('${items.length}', textAlign: TextAlign.center,
                            style: TextStyle(color: colorScheme.onError, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return CustomScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ----- CAJA / MESAS -----
                              if (_cajasActivas)
                                Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    leading: Icon(_cajaAbierta ? Icons.lock_open_outlined : Icons.lock_outline),
                                    title: Text(_cajaAbierta ? 'Caja abierta' : 'Caja pendiente de apertura',
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        _mesasActivas ? 'Mesas activas.' : 'Sin mesas activas.',
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: _mesasActivas ? const Icon(Icons.table_restaurant_outlined) : null,
                                    onTap: _openOperation,
                                  ),
                                ),
                              if (_cajasActivas) const SizedBox(height: 10),

                              // ----- MESA -----
                              if (_mesasActivas)
                                DropdownButtonFormField<int?>(
                                  initialValue: _selectedTableId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Mesa para la venta pendiente',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: colorScheme.surface,
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(value: null, child: Text('Sin mesa')),
                                    ..._tables
                                        .where((t) => t['activo'] != false && (t['estado'] == 'libre' || t['id'] == _selectedTableId))
                                        .map((t) => DropdownMenuItem<int?>(
                                              value: (t['id'] as num).toInt(),
                                              child: Text('${t['nombre']} (${t['estado'] ?? 'libre'})', overflow: TextOverflow.ellipsis),
                                            )),
                                  ],
                                  onChanged: (tableId) {
                                    final table = _tables.where((item) => item['id'] == tableId).firstOrNull;
                                    setState(() {
                                      _selectedTableId = tableId;
                                      _selectedTableName = table?['nombre']?.toString();
                                    });
                                  },
                                ),
                              if (_mesasActivas) const SizedBox(height: 10),

                              // ----- MÉTRICAS COMPACTAS (UNA FILA) -----
                              _buildMetricsRow(context),
                              const SizedBox(height: 12),

                              // ----- BÚSQUEDA + BOTÓN FILTRO -----
                              _buildSearch(context),
                              const SizedBox(height: 10),

                              // ----- CHIPS DE CATEGORÍA -----
                              if (_categories.isNotEmpty) _buildCategoryChips(context),
                              if (_categories.isNotEmpty) const SizedBox(height: 10),

                              // ----- TÍTULO SECCIÓN -----
                              Text(
                                'Productos',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorScheme.onSurface),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),

                      // ----- LISTA DE PRODUCTOS -----
                      if (_filteredProducts.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(30),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  Text('No se encontraron productos.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          sliver: SliverLayoutBuilder(
                            builder: (context, sliverConstraints) {
                              final width = sliverConstraints.crossAxisExtent;
                              final columns = width >= 1000 ? 3 : width >= 650 ? 2 : 1;

                              if (columns == 1) {
                                return SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildProductCard(context, _filteredProducts[index]),
                                    ),
                                    childCount: _filteredProducts.length,
                                  ),
                                );
                              }

                              return SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildProductCard(context, _filteredProducts[index]),
                                  childCount: _filteredProducts.length,
                                ),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: columns == 2 ? 2.1 : 2.0,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }

  // ============================================================
  // WIDGETS DE UI
  // ============================================================

  /// Productos filtrados por texto y categoría.
  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    return _products.where((product) {
      final matchText = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);

      if (!matchText) return false;

      if (_selectedCategoryId == null) return true;

      // Filtrar por categoría usando data_json del producto
      // El campo categoria_id se guarda en data_json al crear/editar
      return _productCategoryId(product) == _selectedCategoryId;
    }).toList();
  }

  int? _productCategoryId(Product product) {
    // Product no tiene categoryId directo; se buscará en la BD via data_json.
    // Como aproximación rápida usamos el índice guardado en la lista _products,
    // que proviene de getProducts() que incluye data_json como campo extra.
    // En su defecto retorna null (se muestra en "Todos").
    return null; // TODO: ampliar Product.fromMap con categoryId desde data_json
  }

  /// Cards de métricas en una sola fila horizontal compacta.
  Widget _buildMetricsRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 62,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _CompactMetric(label: 'Ventas', value: '$_todaySales', color: colorScheme.primary),
            const SizedBox(width: 8),
            _CompactMetric(label: 'Pendientes', value: '$_pendingSales', color: colorScheme.tertiary),
            const SizedBox(width: 8),
            _CompactMetric(label: 'Canceladas', value: '$_cancelledSales', color: colorScheme.secondary),
          ],
        ),
      ),
    );
  }

  /// Chips de categoría horizontal.
  Widget _buildCategoryChips(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          // Chip "Todos"
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('Todos'),
              selected: _selectedCategoryId == null,
              onSelected: (_) => setState(() => _selectedCategoryId = null),
              selectedColor: colorScheme.primary,
              labelStyle: TextStyle(
                color: _selectedCategoryId == null ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          ..._categories.map((cat) {
            final id = _catId(cat);
            final name = (cat['name'] ?? cat['nombre'] ?? '').toString();
            final selected = _selectedCategoryId == id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(name),
                selected: selected,
                onSelected: (_) => setState(() => _selectedCategoryId = selected ? null : id),
                selectedColor: colorScheme.primary,
                labelStyle: TextStyle(
                  color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Campo de búsqueda con sombra reducida + botón de filtro por categoría.
  Widget _buildSearch(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasFilter = _selectedCategoryId != null;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.primary.withAlpha(45)),
              // Sombra mínima
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search, color: colorScheme.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _searchController.clear()),
                      )
                    : null,
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Botón filtro por categoría
        GestureDetector(
          onTap: _openCategoryFilter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: hasFilter ? colorScheme.primary : colorScheme.onSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasFilter ? Icons.filter_alt : Icons.filter_list,
              color: hasFilter ? colorScheme.onPrimary : colorScheme.surface,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 340;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _productCode(context, product),
                    const SizedBox(width: 10),
                    Expanded(child: _productInformation(context, product)),
                  ]),
                  const SizedBox(height: 10),
                  _productBottomActions(context, product, fullWidth: true),
                ],
              );
            }
            return Row(children: [
              _productCode(context, product),
              const SizedBox(width: 12),
              Expanded(child: _productInformation(context, product)),
              const SizedBox(width: 10),
              _productBottomActions(context, product),
            ]);
          },
        ),
      ),
    );
  }

  Widget _productCode(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: colorScheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(14)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(product.code, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          ),
        ),
      ),
    );
  }

  Widget _productInformation(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colorScheme.onSurface)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: product.stock > 0 ? colorScheme.primary.withAlpha(23) : colorScheme.error.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Stock: ${product.stock.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              color: product.stock > 0 ? colorScheme.primary : colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _productBottomActions(BuildContext context, Product product, {bool fullWidth = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    if (fullWidth) {
      return Row(
        children: [
          Expanded(child: Text('\$${product.price.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorScheme.onSurface))),
          ElevatedButton(
            onPressed: () => _addToCart(product),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Agregar'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(child: Text('\$${product.price.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorScheme.onSurface))),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _addToCart(product),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// ============================================================
// DIÁLOGO DE PAGO — TAREA 6: errores siempre DENTRO del diálogo
// ============================================================

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});
  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentRowData {
  _PaymentRowData({required this.id, required this.method, required this.controller});
  final int id;
  String method;
  final TextEditingController controller;
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const List<String> _methods = ['Efectivo', 'Tarjeta', 'Transferencia', 'Cheque'];

  final List<_PaymentRowData> _rows = [];
  int _nextRowId = 0;

  // Error visible DENTRO del diálogo (tarea 6)
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _rows.add(_createRow(method: 'Efectivo', amount: widget.total.toStringAsFixed(2)));
  }

  _PaymentRowData _createRow({String method = 'Efectivo', String amount = '0.00'}) {
    return _PaymentRowData(id: _nextRowId++, method: method, controller: TextEditingController(text: amount));
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.controller.dispose();
    }
    _rows.clear();
    super.dispose();
  }

  void _addPaymentRow() {
    if (!mounted) return;
    setState(() => _rows.add(_createRow()));
  }

  void _removePaymentRow(int rowId) {
    if (!mounted || _rows.length <= 1) return;
    final index = _rows.indexWhere((r) => r.id == rowId);
    if (index < 0) return;
    final row = _rows[index];
    setState(() => _rows.removeAt(index));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.controller.dispose());
  }

  double _parseMoney(String value) {
    final normalized = value.replaceAll(',', '').replaceAll(r'$', '').trim();
    if (normalized.isEmpty || normalized == '.') return 0.0;
    return double.tryParse(normalized) ?? 0.0;
  }

  List<PaymentEntry> _entries() => _rows
      .map((row) => PaymentEntry(method: row.method, amount: _parseMoney(row.controller.text)))
      .where((e) => e.amount > 0)
      .toList();

  void _submit() {
    if (!mounted) return;

    final entries = _entries();

    if (entries.isEmpty) {
      setState(() => _inlineError = 'Debes indicar al menos un pago.');
      return;
    }

    final breakdown = PaymentBreakdown(total: widget.total, payments: entries);

    if (breakdown.totalCollected + 0.005 < widget.total) {
      final falta = breakdown.shortfall.toStringAsFixed(2);
      setState(() => _inlineError = 'Falta por cobrar: \$$falta. Ajusta el monto antes de continuar.');
      return;
    }

    final hasNonCashOverage = breakdown.nonCashAmount > widget.total + 0.005;
    if (hasNonCashOverage) {
      setState(() => _inlineError = 'Tarjeta, transferencia y cheque deben cubrir exactamente el total. No se acepta excedente sin efectivo.');
      return;
    }

    // Todo correcto, limpiar error y confirmar
    setState(() => _inlineError = null);

    Navigator.of(context).pop({
      'payments': entries.map((e) => <String, dynamic>{'method': e.method, 'amount': e.amount}).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cobro y cambio'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Monto a cobrar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Monto a cobrar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('\$${widget.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Filas de pago
                ..._rows.map((row) => Padding(
                  key: ValueKey<int>(row.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildPaymentRow(row),
                )),

                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addPaymentRow,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Agregar tipo de pago'),
                  ),
                ),
                const SizedBox(height: 8),

                // ── ERROR INLINE (TAREA 6) ──────────────────────────
                if (_inlineError != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _inlineError!,
                            style: TextStyle(fontSize: 13, color: Colors.red.shade700, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                // ────────────────────────────────────────────────────

                _buildSummary(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Guardar cobro'),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(_PaymentRowData row) {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildMethodDropdown(row)),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            key: ValueKey<String>('amount-${row.id}'),
            controller: row.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Cantidad',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) {
              if (mounted) setState(() => _inlineError = null);
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Eliminar',
          onPressed: _rows.length > 1 ? () => _removePaymentRow(row.id) : null,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _buildMethodDropdown(_PaymentRowData row) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey<String>('method-${row.id}'),
          value: _methods.contains(row.method) ? row.method : _methods.first,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          items: _methods.map((m) => DropdownMenuItem<String>(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) {
            if (value == null || !mounted) return;
            setState(() {
              row.method = value;
              _inlineError = null;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final entries = _rows.map((row) => PaymentEntry(method: row.method, amount: _parseMoney(row.controller.text))).toList();
    final breakdown = PaymentBreakdown(total: widget.total, payments: entries);
    final totalCollected = breakdown.totalCollected;
    final cashAmount = breakdown.cashAmount;
    final change = breakdown.change;
    final excess = breakdown.excess;
    final shortfall = breakdown.shortfall;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resumen de cobro', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          _summaryRow('Monto a cobrar:', '\$${widget.total.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _summaryRow('Total cobrado:', '\$${totalCollected.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (cashAmount > 0) ...[
            _summaryRow('Efectivo:', '\$${cashAmount.toStringAsFixed(2)}', small: true),
            const SizedBox(height: 6),
          ],
          ...entries.where((e) => e.method != 'Efectivo' && e.amount > 0).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _summaryRow('${e.method}:', '\$${e.amount.toStringAsFixed(2)}', small: true),
          )),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (totalCollected > widget.total + 0.005) ...[
            if (cashAmount > 0)
              _buildSuccessBox('Cambio (efectivo):', '\$${change.toStringAsFixed(2)}')
            else
              _buildWarningBox('\$${excess.toStringAsFixed(2)}'),
          ] else if (totalCollected < widget.total - 0.005)
            _buildErrorBox('\$${shortfall.toStringAsFixed(2)}')
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cobro exacto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.primary)),
                  Icon(Icons.check_circle, color: colorScheme.primary, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool small = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: small ? 11 : 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(width: 8),
        Text(value, style: TextStyle(fontSize: small ? 11 : null, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSuccessBox(String label, String value) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildWarningBox(String value) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Los pagos sin efectivo deben cubrir el importe exacto.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String value) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(6)),
      child: Row(
        children: [
          Expanded(child: Text('Falta por cobrar:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

// ============================================================
// MÉTRICA COMPACTA
// ============================================================

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
        boxShadow: [BoxShadow(color: color.withAlpha(18), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: color.withAlpha(25), shape: BoxShape.circle),
            child: Icon(Icons.trending_up_rounded, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}
