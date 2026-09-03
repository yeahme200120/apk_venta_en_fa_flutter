import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/product.dart';
import '../../core/models/sale_model.dart';
import '../../core/network/api_client.dart';
import '../../core/payments/payment_breakdown.dart';
import '../../core/storage/app_storage.dart';
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

  List<Product> _products = [];
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
    _loadProducts();
    _loadOperationState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyCartChanged();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cartNotifier.dispose();
    super.dispose();
  }

  // ============================================================
  // CARGA DE DATOS
  // ============================================================

  Future<void> _loadProducts() async {
    final items = await _db.getProducts();
    final sales = await _db.getTodaySales();

    if (!mounted) return;

    setState(() {
      _products = items.map(Product.fromMap).toList();
      _todaySales = sales.length;
      _pendingSales = sales.where((sale) => sale['sync_status'] != 'synced').length;
      _cancelledSales = sales.where((sale) => sale['status'] == 'cancelled').length;
      _isLoading = false;
    });
  }

  Future<void> _loadOperationState() async {
    var state = await AppStorage().getOperationState();

    try {
      state = await ApiClient().getOperationStatus();
      await AppStorage().saveOperationState(state);

      if (state['mesas_activas'] == true) {
        _tables = await ApiClient().getTables();
      }
    } catch (_) {
      // Offline: usar último estado guardado.
    }

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
    return _cartNotifier.value
        .map(
          (item) => {
            'product_id': item.product.id,
            'name': item.product.name,
            'quantity': item.quantity,
            'unit_price': item.product.price,
            'total': item.subtotal,
          },
        )
        .toList();
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

    await Navigator.of(cartContext).push(
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartNotifier: _cartNotifier,
          onQuantityChanged: _changeQuantity,
          onRemove: _removeFromCart,
          onClear: _clearCart,
          onCheckout: _confirmSale,
        ),
      ),
    );

    if (!mounted) return;
    _notifyCartChanged();
  }

  Future<void> _openCart() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartNotifier: _cartNotifier,
          onQuantityChanged: _changeQuantity,
          onRemove: _removeFromCart,
          onClear: _clearCart,
          onCheckout: _confirmSale,
        ),
      ),
    );

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
          const SnackBar(
            content: Text('Un cajero debe abrir la caja antes de registrar o cobrar ventas.'),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _savePendingSale() async {
    if (_cartNotifier.value.isEmpty || !await _canOperateSale()) return;

    try {
      if (_pendingSaleId == null) {
        await _db.saveSale(
          uuid: 'sale_${DateTime.now().millisecondsSinceEpoch}',
          items: _currentSaleItems(),
          payments: const [],
          total: _total,
          status: 'pending',
          tableId: _selectedTableId,
          tableName: _selectedTableName,
        );
      } else {
        final updated = await _db.updatePendingSale(
          saleId: _pendingSaleId!,
          items: _currentSaleItems(),
          total: _total,
          tableId: _selectedTableId,
          tableName: _selectedTableName,
        );

        if (!updated) {
          throw StateError('La venta pendiente ya no está disponible.');
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _setCart([]);
      _pendingSaleId = null;
      _selectedTableId = null;
      _selectedTableName = null;
    });

    await _loadProducts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta guardada como pendiente.')));
    }
  }

  // ============================================================
  // CONFIRMAR VENTA (CHECKOUT)
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
      payments: payments
          .map(
            (item) => PaymentEntry(
              method: (item['method'] ?? 'Efectivo').toString(),
              amount: (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0.0,
            ),
          )
          .toList(),
    );

    final cashAmount = breakdown.cashAmount;
    final change = breakdown.change;

    var saleId = _pendingSaleId;

    try {
      if (saleId != null) {
        final paid = await _db.payPendingSale(
          saleId,
          payments: payments,
          paymentMethod: cashAmount > 0 ? 'Efectivo' : 'Mixto',
          cashReceived: cashAmount,
          changeDue: change,
        );

        if (!paid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La venta pendiente ya no está disponible.')),
            );
          }
          return false;
        }
      } else {
        saleId = await _db.saveSale(
          uuid: uuid,
          items: saleItems,
          payments: payments,
          total: _total,
          status: 'paid',
          syncStatus: 'pending',
          paymentMethod: cashAmount > 0 ? 'Efectivo' : 'Mixto',
          cashReceived: cashAmount,
          changeDue: change,
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
      return false;
    }

    final generatedSale = saleId == null ? null : await _db.getSaleById(saleId);

    if (generatedSale != null && mounted) {
      final sale = generatedSale;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            sale: SaleModel(
              id: int.tryParse('${sale['id'] ?? 0}') ?? 0,
              uuidLocal: sale['uuid_local']?.toString() ?? uuid,
              serverId: null,
              businessDate: DateTime.now().toIso8601String().substring(0, 10),
              total: (sale['total'] is num) ? (sale['total'] as num).toDouble() : _total,
              syncStatus: sale['sync_status']?.toString() ?? 'pending',
              status: sale['status']?.toString() ?? 'paid',
              items: saleItems
                  .map(
                    (item) => SaleItemModel(
                      id: 0,
                      saleId: 0,
                      productId: int.tryParse('${item['product_id'] ?? 0}') ?? 0,
                      name: item['name']?.toString() ?? '',
                      quantity: (item['quantity'] is num) ? (item['quantity'] as num).toDouble() : 0.0,
                      unitPrice: (item['unit_price'] is num) ? (item['unit_price'] as num).toDouble() : 0.0,
                      total: (item['total'] is num) ? (item['total'] as num).toDouble() : 0.0,
                    ),
                  )
                  .toList(),
              payments: payments
                  .map(
                    (item) => SalePaymentModel(
                      id: 0,
                      saleId: 0,
                      method: item['method']?.toString() ?? '',
                      amount: (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0.0,
                    ),
                  )
                  .toList(),
              createdAt: DateTime.now().toIso8601String(),
              updatedAt: DateTime.now().toIso8601String(),
            ),
          ),
        ),
      );
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
      SnackBar(
        content: Text(
          'Venta pagada y guardada para sincronización. Cambio: \$${change.toStringAsFixed(2)}',
        ),
      ),
    );

    return true;
  }

  // ============================================================
  // DIÁLOGO DE PAGO
  // ============================================================

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    if (!mounted) {
      return null;
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(total: _total),
    );
  }

  // VER PENDIENTES
  // ============================================================

  Future<void> _showPendingSales() async {
    final sales = (await _db.getTodaySales())
        .where((sale) => sale['status'] == 'pending')
        .toList();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .75,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Ventas pendientes',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (sales.isEmpty)
                  const ListTile(title: Text('No hay ventas pendientes.')),
                ...sales.map(
                  (sale) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    title: Text(
                      'Venta #${sale['id']} — \$${(sale['total'] as num).toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      sale['mesa_nombre'] == null ? 'Aún no pagada' : 'Mesa: ${sale['mesa_nombre']}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Eliminar pendiente',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await _db.deletePendingSale(sale['id'] as int);
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        await _loadProducts();
                      },
                    ),
                    onTap: () async {
                      final items = await _db.getSaleItemsBySaleId(sale['id'] as int);
                      final cart = <CartItem>[];

                      for (final item in items) {
                        Product? product;
                        for (final candidate in _products) {
                          if (candidate.id == item['product_id']) {
                            product = candidate;
                            break;
                          }
                        }
                        if (product == null) continue;
                        cart.add(CartItem(product: product, quantity: (item['quantity'] as num).toInt()));
                      }

                      if (!mounted) return;

                      _setCart(cart);

                      setState(() {
                        _pendingSaleId = sale['id'] as int;
                        _selectedTableId = sale['mesa_id'] as int?;
                        _selectedTableName = sale['mesa_nombre']?.toString();
                      });

                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // OPERACIÓN (CAJA / MESAS)
  // ============================================================

  Future<void> _openOperation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OperationScreen()),
    );
    await _loadOperationState();
  }

  // ============================================================
  // UI - BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F4),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF3F6EE),
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF9AC53B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.point_of_sale, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'Caja',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFF1F2A1A), fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<List<CartItem>>(
            valueListenable: _cartNotifier,
            builder: (context, items, child) {
              final total = items.fold(0.0, (sum, item) => sum + item.subtotal);
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9AC53B),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      items.isEmpty ? 'Sin venta' : 'Total \$${total.toStringAsFixed(2)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              );
            },
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
                            children: [
                              if (_cajasActivas)
                                Card(
                                  margin: EdgeInsets.zero,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    leading: Icon(_cajaAbierta ? Icons.lock_open_outlined : Icons.lock_outline),
                                    title: Text(
                                      _cajaAbierta ? 'Caja abierta' : 'Caja pendiente de apertura',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      _mesasActivas ? 'Mesas activas para esta empresa.' : 'Mesas no activas para esta empresa.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: _mesasActivas ? const Icon(Icons.table_restaurant_outlined) : null,
                                    onTap: _openOperation,
                                  ),
                                ),

                              if (_cajasActivas) const SizedBox(height: 10),

                              if (_mesasActivas)
                                DropdownButtonFormField<int?>(
                                  value: _selectedTableId,
                                  decoration: const InputDecoration(
                                    labelText: 'Mesa para la venta pendiente',
                                    border: OutlineInputBorder(),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('Sin mesa'),
                                    ),
                                    ..._tables
                                        .where(
                                          (table) =>
                                              table['activo'] != false &&
                                              (table['estado'] == 'libre' || table['id'] == _selectedTableId),
                                        )
                                        .map(
                                          (table) => DropdownMenuItem<int?>(
                                            value: (table['id'] as num).toInt(),
                                            child: Text(
                                              '${table['nombre']} (${table['estado'] ?? 'libre'})',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
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

                              _buildSearch(),
                              const SizedBox(height: 12),
                              _buildMetrics(constraints),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Productos',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1F2A1A)),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),

                      if (_filteredProducts.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48, color: Colors.black38),
                                  SizedBox(height: 12),
                                  Text(
                                    'No se encontraron productos.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                          sliver: SliverLayoutBuilder(
                            builder: (context, sliverConstraints) {
                              final width = sliverConstraints.crossAxisExtent;
                              final columns = width >= 1000 ? 3 : width >= 650 ? 2 : 1;

                              if (columns == 1) {
                                return SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final product = _filteredProducts[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: _buildProductCard(product),
                                      );
                                    },
                                    childCount: _filteredProducts.length,
                                  ),
                                );
                              }

                              return SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildProductCard(_filteredProducts[index]),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCart,
        backgroundColor: const Color(0xFF9AC53B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.shopping_cart_outlined),
        label: ValueListenableBuilder<List<CartItem>>(
          valueListenable: _cartNotifier,
          builder: (context, items, child) {
            return Text('Carrito (${items.length})');
          },
        ),
      ),
    );
  }

  // ============================================================
  // WIDGETS DE UI
  // ============================================================

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _products;
    return _products.where((product) {
      return product.name.toLowerCase().contains(query) || product.code.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildSearch() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF9AC53B).withAlpha(45)),
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Buscar producto por nombre o código',
                prefixIcon: Icon(Icons.search, color: Color(0xFF9AC53B)),
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.black54),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2A1A),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.filter_list, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildMetrics(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    int columns;
    if (width < 500) columns = 1;
    else if (width < 800) columns = 2;
    else columns = 3;

    final metrics = [
      _MetricCard(
        label: 'Ventas del día',
        value: '$_todaySales',
        color: const Color(0xFF9AC53B),
      ),
      _MetricCard(
        label: 'Pendientes',
        value: '$_pendingSales',
        color: const Color(0xFFFFB703),
      ),
      _MetricCard(
        label: 'Canceladas',
        value: '$_cancelledSales',
        color: const Color(0xFF1F9D8A),
      ),
    ];

    return GridView.count(
      crossAxisCount: columns,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: columns == 1 ? 4.2 : 2.4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: metrics,
    );
  }

  Widget _buildProductCard(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF9AC53B).withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9AC53B).withAlpha(18),
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
                  Row(
                    children: [
                      _productCode(product),
                      const SizedBox(width: 10),
                      Expanded(child: _productInformation(product)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _productBottomActions(product, fullWidth: true),
                ],
              );
            }

            return Row(
              children: [
                _productCode(product),
                const SizedBox(width: 12),
                Expanded(child: _productInformation(product)),
                const SizedBox(width: 10),
                _productBottomActions(product),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _productCode(Product product) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF9AC53B).withAlpha(30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              product.code,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2B3A1E)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productInformation(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A1A)),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: product.stock > 0 ? const Color(0xFF9AC53B).withAlpha(23) : Colors.red.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Stock: ${product.stock.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              color: product.stock > 0 ? const Color(0xFF2D6A1E) : Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _productBottomActions(Product product, {bool fullWidth = false}) {
    if (fullWidth) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '\$${product.price.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1F2A1A)),
            ),
          ),
          ElevatedButton(
            onPressed: () => _addToCart(product),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9AC53B),
              foregroundColor: Colors.white,
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
        FittedBox(
          child: Text(
            '\$${product.price.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1F2A1A)),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _addToCart(product),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9AC53B),
            foregroundColor: Colors.white,
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
// DIÁLOGO DE PAGO - ESTADO AISLADO
// ============================================================

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.total,
  });

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentRowData {
  _PaymentRowData({
    required this.id,
    required this.method,
    required this.controller,
  });

  final int id;
  String method;
  final TextEditingController controller;
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const List<String> _methods = [
    'Efectivo',
    'Tarjeta',
    'Transferencia',
    'Cheque',
  ];

  final List<_PaymentRowData> _rows = [];
  int _nextRowId = 0;

  @override
  void initState() {
    super.initState();
    _addInitialCashRow();
  }

  void _addInitialCashRow() {
    _rows.add(
      _createRow(
        method: 'Efectivo',
        amount: widget.total.toStringAsFixed(2),
      ),
    );
  }

  _PaymentRowData _createRow({
    String method = 'Efectivo',
    String amount = '0.00',
  }) {
    final row = _PaymentRowData(
      id: _nextRowId++,
      method: method,
      controller: TextEditingController(text: amount),
    );

    return row;
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
    if (!mounted) {
      return;
    }

    setState(() {
      _rows.add(
        _createRow(),
      );
    });
  }

  void _removePaymentRow(int rowId) {
    if (!mounted || _rows.length <= 1) {
      return;
    }

    final index = _rows.indexWhere(
      (row) => row.id == rowId,
    );

    if (index < 0) {
      return;
    }

    final row = _rows[index];

    setState(() {
      _rows.removeAt(index);
    });

    // Se elimina después del setState para que el árbol no tenga
    // una referencia a un controller ya destruido durante el rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      row.controller.dispose();
    });
  }

  double _parseMoney(String value) {
    final normalized = value
        .replaceAll(',', '')
        .replaceAll(r'$','')
        .trim();

    if (normalized.isEmpty || normalized == '.') {
      return 0.0;
    }

    return double.tryParse(normalized) ?? 0.0;
  }

  List<PaymentEntry> _entries() {
    return _rows
        .map(
          (row) => PaymentEntry(
            method: row.method,
            amount: _parseMoney(row.controller.text),
          ),
        )
        .where(
          (entry) => entry.amount > 0,
        )
        .toList();
  }

  void _submit() {
    if (!mounted) {
      return;
    }

    final entries = _entries();

    if (entries.isEmpty) {
      _showMessage(
        'Debes indicar al menos un pago.',
        isError: true,
      );
      return;
    }

    final breakdown = PaymentBreakdown(
      total: widget.total,
      payments: entries,
    );

    if (breakdown.totalCollected + 0.005 < widget.total) {
      final falta = breakdown.shortfall.toStringAsFixed(2);

      _showMessage(
        'Falta por cobrar: \$$falta',
        isError: true,
      );
      return;
    }

    final hasNonCashOverage =
        breakdown.nonCashAmount > widget.total + 0.005;

    if (hasNonCashOverage) {
      _showMessage(
        'Tarjeta, transferencia y cheque deben cubrir exactamente el total.',
        isError: true,
      );
      return;
    }

    Navigator.of(context).pop({
      'payments': entries
          .map(
            (entry) => <String, dynamic>{
              'method': entry.method,
              'amount': entry.amount,
            },
          )
          .toList(),
    });
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    final messenger =
        ScaffoldMessenger.maybeOf(context);

    if (messenger == null) {
      return;
    }

    messenger
        .hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cobro y cambio'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 600,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9AC53B)
                        .withAlpha(26),
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monto a cobrar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '\$${widget.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ..._rows.map(
                  (row) => Padding(
                    key: ValueKey<int>(row.id),
                    padding:
                        const EdgeInsets.only(bottom: 10),
                    child: _buildPaymentRow(row),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addPaymentRow,
                    icon: const Icon(
                      Icons.add_circle_outline,
                    ),
                    label: const Text(
                      'Agregar tipo de pago',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildSummary(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(
            Icons.check_circle_outline,
          ),
          label: const Text('Guardar cobro'),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(
    _PaymentRowData row,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildMethodDropdown(row),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey<String>(
                  'amount-${row.id}',
                ),
                controller: row.controller,
                keyboardType:
                    const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction:
                    TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Eliminar forma de pago',
              onPressed: _rows.length > 1
                  ? () => _removePaymentRow(row.id)
                  : null,
              icon: const Icon(
                Icons.delete_outline,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMethodDropdown(
    _PaymentRowData row,
  ) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey.shade400,
        ),
        borderRadius:
            BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey<String>(
            'method-${row.id}',
          ),
          value: _methods.contains(row.method)
              ? row.method
              : _methods.first,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          items: _methods
              .map(
                (method) => DropdownMenuItem<String>(
                  value: method,
                  child: Text(
                    method,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null || !mounted) {
              return;
            }

            setState(() {
              row.method = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final entries = _rows
        .map(
          (row) => PaymentEntry(
            method: row.method,
            amount: _parseMoney(
              row.controller.text,
            ),
          ),
        )
        .toList();

    final breakdown = PaymentBreakdown(
      total: widget.total,
      payments: entries,
    );

    final totalCollected =
        breakdown.totalCollected;
    final cashAmount =
        breakdown.cashAmount;
    final change =
        breakdown.change;
    final excess =
        breakdown.excess;
    final shortfall =
        breakdown.shortfall;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de cobro',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          _summaryRow(
            'Monto a cobrar:',
            '\$${widget.total.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Total cobrado:',
            '\$${totalCollected.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (cashAmount > 0) ...[
            _summaryRow(
              'Efectivo:',
              '\$${cashAmount.toStringAsFixed(2)}',
              small: true,
            ),
            const SizedBox(height: 6),
          ],
          ...entries
              .where(
                (entry) =>
                    entry.method != 'Efectivo' &&
                    entry.amount > 0,
              )
              .map(
                (entry) => Padding(
                  padding:
                      const EdgeInsets.only(bottom: 6),
                  child: _summaryRow(
                    '${entry.method}:',
                    '\$${entry.amount.toStringAsFixed(2)}',
                    small: true,
                  ),
                ),
              ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          if (totalCollected > widget.total + 0.005) ...[
            if (cashAmount > 0)
              _buildSuccessBox(
                'Cambio (efectivo):',
                '\$${change.toStringAsFixed(2)}',
              )
            else
              _buildWarningBox(
                '\$${excess.toStringAsFixed(2)}',
              ),
          ] else if (totalCollected < widget.total - 0.005)
            _buildErrorBox(
              '\$${shortfall.toStringAsFixed(2)}',
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    const Color(0xFF9AC53B)
                        .withAlpha(20),
                borderRadius:
                    BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cobro exacto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D6A1E),
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    color: Color(0xFF2D6A1E),
                    size: 18,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool small = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              color: Colors.black54,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: small ? 11 : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBox(
    String label,
    String value,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            const Color(0xFF9AC53B)
                .withAlpha(20),
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D6A1E),
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D6A1E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(26),
        borderRadius:
            BorderRadius.circular(6),
        border: Border.all(
          color: Colors.orange.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Los pagos sin efectivo deben cubrir el importe exacto.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(20),
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Falta por cobrar:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(80)),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.trending_up_rounded, color: color, size: 20),
          ),
        ],
      ),
    );
  }
}