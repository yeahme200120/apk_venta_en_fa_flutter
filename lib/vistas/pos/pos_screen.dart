import 'dart:async';

import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../core/database/local_db.dart';
import '../../core/models/product.dart';
import '../../core/models/sale_model.dart';
import '../../core/network/api_client.dart';
import '../../core/payments/payment_breakdown.dart';
import '../../core/storage/app_storage.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/printer_service.dart';
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
  final PrinterService _printerService = PrinterService();

  StreamSubscription<void>? _salesChangesSubscription;
  bool _refreshing = false;
  bool _syncing = false;
  bool _refreshQueued = false;

  List<Product> _products = [];
  List<Map<String, dynamic>> _categories = const [];
  int? _selectedCategoryId;
  bool _isCardView = false;
  bool _isLoadingCategories = false;
  bool _isLoading = true;

  int _todaySales = 0;
  int _pendingSales = 0;
  int _cancelledSales = 0;

  int? _pendingSaleId;
  bool _processingSale = false;

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
    _loadCategories();
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

  Future<void> _loadCategories() async {
    if (_isLoadingCategories) return;

    _isLoadingCategories = true;

    try {
      final rows = await _db.getCategories();
      final categories = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted) return;

      final availableIds = categories
          .map((category) => _parseCategoryId(category['id']))
          .whereType<int>()
          .toSet();

      setState(() {
        _categories = categories;
        if (_selectedCategoryId != null &&
            !availableIds.contains(_selectedCategoryId)) {
          _selectedCategoryId = null;
        }
      });
    } catch (error) {
      debugPrint('No fue posible cargar categorías: $error');
    } finally {
      _isLoadingCategories = false;
    }
  }

  int? _parseCategoryId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _categoryName(Map<String, dynamic> category) {
    return (category['name'] ?? category['nombre'] ?? 'Sin nombre').toString();
  }

  Future<void> _loadProducts({bool showLoading = false}) async {
    if (_refreshing) return;

    _refreshing = true;

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final items = await _db.getProducts();
      final sales = await _db.getTodaySales();

      if (!mounted) return;

      setState(() {
        _products = items.map(Product.fromMap).toList();
        _todaySales = sales.length;
        _pendingSales = sales
            .where((sale) => sale['sync_status'] != 'synced')
            .length;
        _cancelledSales = sales
            .where((sale) => sale['status'] == 'cancelled')
            .length;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible actualizar la caja: $error'),
        ),
      );
    } finally {
      _refreshing = false;
    }
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

  Future<void> _refreshLocalDataSilently() async {
    await _handleSalesChanged();
  }

  Future<void> _refreshAll() async {
    if (!mounted || _syncing) return;

    setState(() {
      _syncing = true;
    });

    try {
      try {
        final offline = await AppStorage().isOfflineSession();
        if (!offline) {
          await SyncService().syncPull();
        }
      } catch (error) {
        debugPrint('ℹ️ Actualización remota omitida: $error');
      }

      await _loadProducts();
      await _loadOperationState();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caja actualizada correctamente.'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible actualizar la caja: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
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

  bool _canAddProduct(Product product) {
    // Los productos no inventariables no dependen del stock.
    if (!product.isInventoriable) {
      return true;
    }

    // Los productos inventariables requieren existencia disponible.
    return product.stock > 0;
  }

  void _addToCart(Product product) {
    if (!_canAddProduct(product)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El producto no tiene stock disponible.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final current = List<CartItem>.from(_cartNotifier.value);
    final index = current.indexWhere((item) => item.product.id == product.id);

    if (index >= 0) {
      final existing = current[index];

      if (product.isInventoriable && existing.quantity >= product.stock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay más existencia disponible.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      current[index] = CartItem(
        product: existing.product,
        quantity: existing.quantity + 1,
      );
    } else {
      current.add(
        CartItem(
          product: product,
          quantity: 1,
        ),
      );
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
    if (_processingSale) return false;

    if (_cartNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos al carrito antes de confirmar.')),
      );
      return false;
    }

    if (!await _canOperateSale()) return false;

    _processingSale = true;

    try {
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
          paymentMethod: _paymentMethodLabel(payments),
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
          paymentMethod: _paymentMethodLabel(payments),
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

    if (saleId != null) {
      final printResult = await _printSaleAutomatically(
        saleId: saleId,
        saleItems: saleItems,
        payments: payments,
        total: _total,
        cashAmount: cashAmount,
        change: change,
        uuid: uuid,
      );

      if (mounted && !printResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Venta guardada correctamente, pero no se imprimió el ticket: ${printResult.message}',
            ),
          ),
        );
      }
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
    } finally {
      _processingSale = false;
    }
  }

  Future<TicketConfig> _ticketConfigForPrinting() async {
    final saved = await AppStorage().getTicketConfig();
    final company = await _db.getCompany();
    final paper = saved['papel']?.toString().trim() == '80mm'
        ? PaperSize.mm80
        : PaperSize.mm58;

    return TicketConfig(
      empresa: company?['nombre']?.toString() ?? 'Mi Empresa',
      rfc: company?['rfc']?.toString(),
      direccion: company?['direccion']?.toString(),
      telefono: company?['telefono']?.toString(),
      email: company?['email_contacto']?.toString(),
      encabezado: saved['cabecera']?.toString(),
      pie: saved['pie_pagina']?.toString() ?? 'Gracias por su compra',
      paperSize: paper,
    );
  }

  String _paymentMethodLabel(List<Map<String, dynamic>> payments) {
    final methods = payments
        .map((item) => item['method']?.toString().trim() ?? '')
        .where((method) => method.isNotEmpty)
        .toSet();

    if (methods.length == 1) return methods.first;
    if (methods.length > 1) return 'Mixto';
    return 'Efectivo';
  }

  Future<PrintOperationResult> _printSaleAutomatically({
    required int saleId,
    required List<Map<String, dynamic>> saleItems,
    required List<Map<String, dynamic>> payments,
    required double total,
    required double cashAmount,
    required double change,
    required String uuid,
  }) async {
    try {
      var connected = await _printerService.bluetoothConnected();

      if (!connected) {
        connected = await _printerService.reconnectSelectedPrinter();
      }

      if (!connected) {
        return PrintOperationResult.error(
          'No hay una impresora Bluetooth conectada o seleccionada.',
        );
      }

      final config = await _ticketConfigForPrinting();
      final generatedSale = await _db.getSaleById(saleId);
      final sale = generatedSale ?? <String, dynamic>{};

      final saleMap = <String, dynamic>{
        'id': sale['id'] ?? saleId,
        'uuid_local': sale['uuid_local'] ?? uuid,
        'folio': sale['folio'] ?? sale['numero'] ?? saleId,
        'fecha': sale['created_at'] ?? sale['createdAt'] ?? DateTime.now().toIso8601String(),
        'metodoPago': _paymentMethodLabel(payments),
        'subtotal': total,
        'total': total,
        // Aquí se conserva el efectivo REAL entregado.
        // El cambio se maneja por separado y nunca se descuenta del pago.
        'recibido': cashAmount,
        'cambio': change,
        'items': saleItems,
      };

      return await _printerService.printSale(
        saleMap,
        config: config,
      );
    } catch (error) {
      return PrintOperationResult.error(
        'No fue posible imprimir el ticket: $error',
      );
    }
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainerHighest,
        titleSpacing: 12,
        title: Text(
          'Caja',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _syncing ? null : _refreshAll,
            icon: _syncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
          ValueListenableBuilder<List<CartItem>>(
            valueListenable: _cartNotifier,
            builder: (context, items, child) {
              return Padding(
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
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${items.length}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
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
                                      _mesasActivas
                                          ? 'Mesas activas para esta empresa.'
                                          : 'Mesas no activas para esta empresa.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: _mesasActivas
                                        ? const Icon(Icons.table_restaurant_outlined)
                                        : null,
                                    onTap: _openOperation,
                                  ),
                                ),
                              if (_cajasActivas) const SizedBox(height: 10),
                              if (_mesasActivas)
                                DropdownButtonFormField<int?>(
                                  value: _selectedTableId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Mesa para la venta pendiente',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: colorScheme.surface,
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
                                              (table['estado'] == 'libre' ||
                                                  table['id'] == _selectedTableId),
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
                                    final table = _tables
                                        .where((item) => item['id'] == tableId)
                                        .firstOrNull;
                                    setState(() {
                                      _selectedTableId = tableId;
                                      _selectedTableName = table?['nombre']?.toString();
                                    });
                                  },
                                ),
                              if (_mesasActivas) const SizedBox(height: 10),
                              _buildSearch(context),
                              const SizedBox(height: 12),
                              _buildMetrics(context, constraints),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Productos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      if (_filteredProducts.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(30),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 48,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No se encontraron productos.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          sliver: _buildProductSliver(context),
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

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();

    return _products.where((product) {
      final matchesQuery = query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);

      final matchesCategory = _selectedCategoryId == null ||
          product.categoryId == _selectedCategoryId;

      return matchesQuery && matchesCategory;
    }).toList();
  }

  String _categoryLabel(int categoryId) {
    for (final category in _categories) {
      if (_parseCategoryId(category['id']) == categoryId) {
        return _categoryName(category);
      }
    }
    return 'Sin categoría';
  }

  Widget _buildSearch(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.primary.withAlpha(45)),
          ),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar producto por nombre, código o SKU',
              prefixIcon: Icon(Icons.search, color: colorScheme.primary),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: InputBorder.none,
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;

            final category = DropdownButtonFormField<int?>(
              value: _selectedCategoryId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Categoría',
                prefixIcon: const Icon(Icons.category_outlined),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: colorScheme.surface,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todas las categorías'),
                ),
                ..._categories.map((category) {
                  final id = _parseCategoryId(category['id']);
                  if (id == null) return null;
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text(
                      _categoryName(category),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).whereType<DropdownMenuItem<int?>>(),
              ],
              onChanged: (categoryId) {
                setState(() {
                  _selectedCategoryId = categoryId;
                });
              },
            );

            final viewToggle = ToggleButtons(
              isSelected: [_isCardView == false, _isCardView == true],
              onPressed: (index) {
                setState(() {
                  _isCardView = index == 1;
                });
              },
              borderRadius: BorderRadius.circular(12),
              constraints: const BoxConstraints(minHeight: 56, minWidth: 54),
              children: const [
                Tooltip(
                  message: 'Vista de lista',
                  child: Icon(Icons.view_list_outlined),
                ),
                Tooltip(
                  message: 'Vista de tarjetas',
                  child: Icon(Icons.grid_view_outlined),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  category,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${_filteredProducts.length} productos',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      viewToggle,
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: category),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_filteredProducts.length} productos',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    viewToggle,
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildProductSliver(BuildContext context) {
    if (!_isCardView) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final product = _filteredProducts[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildProductListItem(context, product),
            );
          },
          childCount: _filteredProducts.length,
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, sliverConstraints) {
        final width = sliverConstraints.crossAxisExtent;

        // La cantidad de columnas se adapta al espacio real disponible.
        // En pantallas amplias las tarjetas quedan en una sola fila por
        // registro; en tablet y móvil se reduce progresivamente.
        final columns = width >= 920
            ? 3
            : width >= 560
                ? 2
                : 1;

        final cardHeight = width >= 920
            ? 154.0
            : width >= 560
                ? 158.0
                : 152.0;

        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildProductCard(
              context,
              _filteredProducts[index],
            ),
            childCount: _filteredProducts.length,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight,
          ),
        );
      },
    );
  }

  Widget _buildProductListItem(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    final canAdd = _canAddProduct(product);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _productCode(context, product),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.categoryId == null
                              ? 'Sin categoría'
                              : _categoryLabel(product.categoryId!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _stockChip(context, product),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${product.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: canAdd ? () => _addToCart(product) : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Agregar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMetrics(BuildContext context, BoxConstraints constraints) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = constraints.maxWidth;

    final columns = width >= 700
        ? 3
        : width >= 500
            ? 2
            : 1;

    final metrics = [
      _MetricCard(
        label: 'Ventas del día',
        value: '$_todaySales',
        color: colorScheme.primary,
        icon: Icons.point_of_sale_rounded,
      ),
      _MetricCard(
        label: 'Pendientes',
        value: '$_pendingSales',
        color: colorScheme.tertiary,
        icon: Icons.pending_actions_rounded,
      ),
      _MetricCard(
        label: 'Canceladas',
        value: '$_cancelledSales',
        color: colorScheme.error,
        icon: Icons.cancel_outlined,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: columns == 3
            ? 92
            : columns == 2
                ? 94
                : 88,
      ),
      itemBuilder: (context, index) => metrics[index],
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    final canAdd = _canAddProduct(product);
    final category = product.categoryId == null
        ? 'Sin categoría'
        : _categoryLabel(product.categoryId!);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: colorScheme.outlineVariant.withAlpha(115),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.15,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        product.code.isEmpty ? category : product.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                _stockChip(context, product),
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '\$${product.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canAdd ? () => _addToCart(product) : null,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Agregar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stockChip(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasStock = product.stock > 0;
    final color = !product.isInventoriable
        ? colorScheme.primary
        : hasStock
            ? colorScheme.primary
            : colorScheme.error;
    final label = !product.isInventoriable
        ? 'Sin inventario'
        : 'Stock: ${product.stock.toStringAsFixed(0)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(23),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _productCode(BuildContext context, Product product) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              product.code,
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productInformation(BuildContext context, Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: product.stock > 0 ? Theme.of(context).colorScheme.primary.withAlpha(23) : Theme.of(context).colorScheme.error.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Stock: ${product.stock.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              color: product.stock > 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _productBottomActions(BuildContext context, Product product, {bool fullWidth = false}) {
    if (fullWidth) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '\$${product.price.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          ElevatedButton(
            onPressed: () => _addToCart(product),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _addToCart(product),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
            isError ? Theme.of(context).colorScheme.error : null,
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
                    color: Theme.of(context).colorScheme.primary
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
                    Theme.of(context).colorScheme.primary
                        .withAlpha(20),
                borderRadius:
                    BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cobro exacto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
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
            Theme.of(context).colorScheme.primary
                .withAlpha(20),
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
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
        color: Theme.of(context).colorScheme.tertiary.withAlpha(26),
        borderRadius:
            BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withAlpha(100),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Los pagos sin efectivo deben cubrir el importe exacto.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.tertiary,
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
        color: Theme.of(context).colorScheme.error.withAlpha(20),
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Falta por cobrar:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.error,
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
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withAlpha(65),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
