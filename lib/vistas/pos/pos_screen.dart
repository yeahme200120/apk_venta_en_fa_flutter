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
  State<PosScreen> createState() => PosScreenState();
}

class PosScreenState extends State<PosScreen> {
  final LocalDb _db = LocalDb();

  final TextEditingController _searchController =
      TextEditingController();

  final ValueNotifier<List<CartItem>> _cartNotifier =
      ValueNotifier<List<CartItem>>([]);

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

  ValueNotifier<List<CartItem>> get cartNotifier =>
      _cartNotifier;

  // ============================================================
  // CARRITO - NOTIFICACIÓN AL HOME SHELL
  // ============================================================

  void _notifyCartChanged() {
    widget.onCartChanged?.call(
      _cartNotifier.value.length,
    );
  }

  void _setCart(List<CartItem> cart) {
    _cartNotifier.value = List<CartItem>.from(cart);
    _notifyCartChanged();
  }

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadProducts();
    _loadOperationState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

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
  // CARGA DE PRODUCTOS
  // ============================================================

  Future<void> _loadProducts() async {
    try {
      final items = await _db.getProducts();
      final sales = await _db.getTodaySales();

      if (!mounted) {
        return;
      }

      setState(() {
        _products = items.map(Product.fromMap).toList();

        _todaySales = sales.length;

        _pendingSales = sales
            .where(
              (sale) => sale['sync_status'] != 'synced',
            )
            .length;

        _cancelledSales = sales
            .where(
              (sale) => sale['status'] == 'cancelled',
            )
            .length;

        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        '❌ Error cargando productos: $error',
      );

      debugPrint(
        '$stackTrace',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error cargando productos: $error',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ============================================================
  // ESTADO OPERATIVO
  // ============================================================

  Future<void> _loadOperationState() async {
    var state =
        await AppStorage().getOperationState();

    try {
      state =
          await ApiClient().getOperationStatus();

      await AppStorage().saveOperationState(
        state,
      );

      if (state['mesas_activas'] == true) {
        try {
          _tables =
              await ApiClient().getTables();
        } catch (error) {
          debugPrint(
            '⚠️ Error cargando mesas: $error',
          );
        }
      } else {
        _tables = const [];
      }
    } catch (error) {
      debugPrint(
        '⚠️ Usando estado operativo local: $error',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _cajasActivas =
          state['cajas_activas'] == true;

      _mesasActivas =
          state['mesas_activas'] == true;

      _cajaAbierta =
          state['caja_abierta'] != null;
    });
  }

  // ============================================================
  // ELEMENTOS DE VENTA
  // ============================================================

  List<Map<String, dynamic>> _currentSaleItems() {
    return _cartNotifier.value
        .map(
          (item) => <String, dynamic>{
            'product_id': item.product.id,
            'name': item.product.name,
            'quantity': item.quantity,
            'unit_price': item.product.price,
            'total': item.subtotal,
          },
        )
        .toList();
  }

  double get _total {
    return _cartNotifier.value.fold(
      0.0,
      (sum, item) => sum + item.subtotal,
    );
  }

  // ============================================================
  // CARRITO
  // ============================================================

  void _addToCart(Product product) {
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El producto no tiene existencia disponible.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final current =
        List<CartItem>.from(
      _cartNotifier.value,
    );

    final index = current.indexWhere(
      (item) =>
          item.product.id == product.id,
    );

    if (index >= 0) {
      final existing = current[index];

      if (existing.quantity >= product.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No puedes agregar más unidades que el stock disponible.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

        return;
      }

      current[index] = CartItem(
        product: existing.product,
        quantity:
            existing.quantity + 1,
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

  void _changeQuantity(
    int productId,
    int delta,
  ) {
    final current =
        List<CartItem>.from(
      _cartNotifier.value,
    );

    final index = current.indexWhere(
      (item) =>
          item.product.id == productId,
    );

    if (index == -1) {
      return;
    }

    final item = current[index];

    final newQty =
        item.quantity + delta;

    if (newQty <= 0) {
      current.removeAt(index);
    } else {
      if (newQty > item.product.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La cantidad supera el stock disponible.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

        return;
      }

      current[index] = CartItem(
        product: item.product,
        quantity: newQty,
      );
    }

    _setCart(current);
  }

  void _removeFromCart(int productId) {
    final current =
        List<CartItem>.from(
      _cartNotifier.value,
    );

    current.removeWhere(
      (item) =>
          item.product.id == productId,
    );

    _setCart(current);
  }

  void _clearCart() {
    _setCart([]);
  }

  // ============================================================
  // ABRIR CARRITO
  // ============================================================

  Future<void> openCart(
    BuildContext context,
  ) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CartScreen(
          cartNotifier:
              _cartNotifier,
          onQuantityChanged:
              _changeQuantity,
          onRemove:
              _removeFromCart,
          onClear:
              _clearCart,
          onCheckout:
              _confirmSale,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    _notifyCartChanged();
  }

  // ============================================================
  // VALIDAR OPERACIÓN
  // ============================================================

  Future<bool> _canOperateSale() async {
    await _loadOperationState();

    if (_cajasActivas &&
        !_cajaAbierta) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Un cajero debe abrir la caja antes de registrar o cobrar ventas.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return false;
    }

    return true;
  }

  // ============================================================
  // GUARDAR VENTA PENDIENTE
  // ============================================================

  Future<void> _savePendingSale() async {
    if (_cartNotifier.value.isEmpty) {
      return;
    }

    if (!await _canOperateSale()) {
      return;
    }

    try {
      if (_pendingSaleId == null) {
        await _db.saveSale(
          uuid:
              'sale_${DateTime.now().millisecondsSinceEpoch}',
          items: _currentSaleItems(),
          payments: const [],
          total: _total,
          status: 'pending',
          tableId:
              _selectedTableId,
          tableName:
              _selectedTableName,
        );
      } else {
        final updated =
            await _db.updatePendingSale(
          saleId:
              _pendingSaleId!,
          items:
              _currentSaleItems(),
          total:
              _total,
          tableId:
              _selectedTableId,
          tableName:
              _selectedTableName,
        );

        if (!updated) {
          throw StateError(
            'La venta pendiente ya no está disponible.',
          );
        }
      }
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.toString(),
          ),
          behavior:
              SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (!mounted) {
      return;
    }

    _setCart([]);

    setState(() {
      _pendingSaleId = null;
      _selectedTableId = null;
      _selectedTableName = null;
    });

    await _loadProducts();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Venta guardada como pendiente.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // CHECKOUT
  // ============================================================

  Future<bool> _confirmSale() async {
    if (_cartNotifier.value.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Agrega productos al carrito antes de confirmar.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      return false;
    }

    if (!await _canOperateSale()) {
      return false;
    }

    final paymentData =
        await _showPaymentDialog();

    if (paymentData == null) {
      return false;
    }

    final uuid =
        'sale_${DateTime.now().millisecondsSinceEpoch}';

    final saleItems =
        _currentSaleItems();

    final payments =
        (paymentData['payments']
                as List<Map<String, dynamic>>?) ??
            const [];

    final breakdown =
        PaymentBreakdown(
      total: _total,
      payments: payments
          .map(
            (item) => PaymentEntry(
              method:
                  (item['method'] ??
                          'Efectivo')
                      .toString(),
              amount:
                  item['amount']
                          is num
                      ? (item['amount']
                              as num)
                          .toDouble()
                      : 0.0,
            ),
          )
          .toList(),
    );

    final cashAmount =
        breakdown.cashAmount;

    final change =
        breakdown.change;

    var saleId =
        _pendingSaleId;

    try {
      if (saleId != null) {
        final paid =
            await _db.payPendingSale(
          saleId,
          payments:
              payments,
          paymentMethod:
              cashAmount > 0
                  ? 'Efectivo'
                  : 'Mixto',
          cashReceived:
              cashAmount,
          changeDue:
              change,
        );

        if (!paid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'La venta pendiente ya no está disponible.',
                ),
                behavior:
                    SnackBarBehavior.floating,
              ),
            );
          }

          return false;
        }
      } else {
        saleId =
            await _db.saveSale(
          uuid:
              uuid,
          items:
              saleItems,
          payments:
              payments,
          total:
              _total,
          status:
              'paid',
          syncStatus:
              'pending',
          paymentMethod:
              cashAmount > 0
                  ? 'Efectivo'
                  : 'Mixto',
          cashReceived:
              cashAmount,
          changeDue:
              change,
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message.toString(),
            ),
            behavior:
                SnackBarBehavior.floating,
          ),
        );
      }

      return false;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error guardando la venta: $error',
            ),
            behavior:
                SnackBarBehavior.floating,
          ),
        );
      }

      return false;
    }

    final generatedSale =
        saleId == null
            ? null
            : await _db.getSaleById(
                saleId,
              );

    if (generatedSale != null &&
        mounted) {
      final sale =
          generatedSale;

      final saleModel =
          SaleModel(
        id:
            int.tryParse(
                  '${sale['id'] ?? 0}',
                ) ??
                0,
        uuidLocal:
            sale['uuid_local']
                    ?.toString() ??
                uuid,
        serverId:
            null,
        businessDate:
            DateTime.now()
                .toIso8601String()
                .substring(
                  0,
                  10,
                ),
        total:
            sale['total']
                    is num
                ? (sale['total']
                        as num)
                    .toDouble()
                : _total,
        syncStatus:
            sale['sync_status']
                    ?.toString() ??
                'pending',
        status:
            sale['status']
                    ?.toString() ??
                'paid',
        items:
            saleItems
                .map(
                  (item) =>
                      SaleItemModel(
                    id: 0,
                    saleId: 0,
                    productId:
                        int.tryParse(
                              '${item['product_id'] ?? 0}',
                            ) ??
                            0,
                    name:
                        item['name']
                                ?.toString() ??
                            '',
                    quantity:
                        item['quantity']
                                is num
                            ? (item['quantity']
                                    as num)
                                .toDouble()
                            : 0.0,
                    unitPrice:
                        item['unit_price']
                                is num
                            ? (item['unit_price']
                                    as num)
                                .toDouble()
                            : 0.0,
                    total:
                        item['total']
                                is num
                            ? (item['total']
                                    as num)
                                .toDouble()
                            : 0.0,
                  ),
                )
                .toList(),
        payments:
            payments
                .map(
                  (item) =>
                      SalePaymentModel(
                    id: 0,
                    saleId: 0,
                    method:
                        item['method']
                                ?.toString() ??
                            '',
                    amount:
                        item['amount']
                                is num
                            ? (item['amount']
                                    as num)
                                .toDouble()
                            : 0.0,
                  ),
                )
                .toList(),
        createdAt:
            DateTime.now()
                .toIso8601String(),
        updatedAt:
            DateTime.now()
                .toIso8601String(),
      );

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SaleDetailScreen(
            sale: saleModel,
          ),
        ),
      );
    }

    if (!mounted) {
      return true;
    }

    _setCart([]);

    setState(() {
      _pendingSaleId = null;
      _selectedTableId = null;
      _selectedTableName = null;
    });

    await _loadProducts();

    if (!mounted) {
      return true;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Venta pagada y guardada para sincronización. Cambio: \$${change.toStringAsFixed(2)}',
        ),
        behavior:
            SnackBarBehavior.floating,
      ),
    );

    return true;
  }

  // ============================================================
  // DIÁLOGO DE PAGO
  // ============================================================

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    const methods = <String>[
      'Efectivo',
      'Tarjeta',
      'Transferencia',
      'Cheque',
    ];

    final rows = <_PaymentRow>[
      _PaymentRow(
        method: 'Efectivo',
        controller:
            TextEditingController(
          text: _total.toStringAsFixed(2),
        ),
      ),
    ];

    Map<String, dynamic>? result;

    try {
      result =
          await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (
              context,
              setDialogState,
            ) {
              final colors =
                  Theme.of(context)
                      .colorScheme;

              return AlertDialog(
                title: const Text(
                  'Cobro y cambio',
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(
                      maxHeight: 600,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize:
                            MainAxisSize.min,
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.all(
                              12,
                            ),
                            decoration:
                                BoxDecoration(
                              color: colors
                                  .primaryContainer,
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                10,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  'Monto a cobrar',
                                  style: Theme.of(
                                    context,
                                  )
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        color: colors
                                            .onPrimaryContainer,
                                      ),
                                ),
                                const SizedBox(
                                  height: 4,
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment:
                                      Alignment
                                          .centerLeft,
                                  child: Text(
                                    '\$${_total.toStringAsFixed(2)}',
                                    style: Theme.of(
                                      context,
                                    )
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: colors
                                              .onPrimaryContainer,
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(
                            height: 12,
                          ),

                          ...List.generate(
                            rows.length,
                            (index) {
                              final row =
                                  rows[index];

                              return Padding(
                                padding:
                                    const EdgeInsets
                                        .only(
                                  bottom: 10,
                                ),
                                child: LayoutBuilder(
                                  builder: (
                                    context,
                                    constraints,
                                  ) {
                                    final compact =
                                        constraints
                                                .maxWidth <
                                            400;

                                    if (compact) {
                                      return Column(
                                        children: [
                                          _paymentMethodDropdown(
                                            row,
                                            methods,
                                            setDialogState,
                                          ),
                                          const SizedBox(
                                            height: 8,
                                          ),
                                          Row(
                                            children: [
                                              Expanded(
                                                child:
                                                    _paymentAmountField(
                                                  row,
                                                  setDialogState,
                                                ),
                                              ),
                                              const SizedBox(
                                                width: 4,
                                              ),
                                              IconButton(
                                                tooltip:
                                                    'Eliminar pago',
                                                onPressed:
                                                    rows.length >
                                                            1
                                                        ? () {
                                                            setDialogState(
                                                              () {
                                                                final controller =
                                                                    rows[index]
                                                                        .controller;

                                                                rows.removeAt(
                                                                    index);

                                                                controller
                                                                    .dispose();
                                                              },
                                                            );
                                                          }
                                                        : null,
                                                icon:
                                                    const Icon(
                                                  Icons
                                                      .delete_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child:
                                              _paymentMethodDropdown(
                                            row,
                                            methods,
                                            setDialogState,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 8,
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child:
                                              _paymentAmountField(
                                            row,
                                            setDialogState,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 4,
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Eliminar pago',
                                          onPressed:
                                              rows.length >
                                                      1
                                                  ? () {
                                                      setDialogState(
                                                        () {
                                                          final controller =
                                                              rows[index]
                                                                  .controller;

                                                          rows.removeAt(
                                                              index);

                                                          controller
                                                              .dispose();
                                                        },
                                                      );
                                                    }
                                                  : null,
                                          icon:
                                              const Icon(
                                            Icons
                                                .delete_outline,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              );
                            },
                          ),

                          const SizedBox(
                            height: 2,
                          ),

                          TextButton.icon(
                            onPressed: () {
                              rows.add(
                                _PaymentRow(
                                  method:
                                      'Efectivo',
                                  controller:
                                      TextEditingController(
                                    text: '0.00',
                                  ),
                                ),
                              );

                              setDialogState(
                                () {},
                              );
                            },
                            icon: const Icon(
                              Icons
                                  .add_circle_outline,
                            ),
                            label:
                                const Text(
                              'Agregar tipo de pago',
                            ),
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          Container(
                            width:
                                double.infinity,
                            padding:
                                const EdgeInsets.all(
                              12,
                            ),
                            decoration:
                                BoxDecoration(
                              color: colors
                                  .surfaceContainerHighest,
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                10,
                              ),
                              border:
                                  Border.all(
                                color: colors
                                    .outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  'Resumen de cobro',
                                  style: Theme.of(
                                    context,
                                  )
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: colors
                                            .onSurface,
                                        fontWeight:
                                            FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(
                                  height: 10,
                                ),
                                ..._buildPaymentSummary(
                                  rows,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
                    child:
                        const Text(
                      'Cancelar',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final entries =
                          rows
                              .map(
                                (row) =>
                                    PaymentEntry(
                                  method:
                                      row.method,
                                  amount:
                                      _parseMoney(
                                    row.controller
                                        .text,
                                  ),
                                ),
                              )
                              .where(
                                (entry) =>
                                    entry.amount >
                                    0,
                              )
                              .toList();

                      if (entries.isEmpty) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Debes indicar al menos un pago.',
                            ),
                            behavior:
                                SnackBarBehavior
                                    .floating,
                          ),
                        );
                        return;
                      }

                      final breakdown =
                          PaymentBreakdown(
                        total: _total,
                        payments:
                            entries,
                      );

                      if (breakdown
                              .totalCollected <
                          _total) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Falta por cobrar: \$${breakdown.shortfall.toStringAsFixed(2)}',
                            ),
                            behavior:
                                SnackBarBehavior
                                    .floating,
                          ),
                        );
                        return;
                      }

                      if (breakdown
                              .nonCashAmount >
                          _total) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Tarjeta, transferencia y cheque deben cubrir exactamente el total.',
                            ),
                            behavior:
                                SnackBarBehavior
                                    .floating,
                          ),
                        );
                        return;
                      }

                      Navigator.of(
                        dialogContext,
                      ).pop(
                        <String, dynamic>{
                          'payments':
                              entries
                                  .map(
                                    (entry) =>
                                        <String, dynamic>{
                                      'method':
                                          entry.method,
                                      'amount':
                                          entry.amount,
                                    },
                                  )
                                  .toList(),
                        },
                      );
                    },
                    icon: const Icon(
                      Icons.check_circle_outline,
                    ),
                    label: const Text(
                      'Guardar cobro',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      for (final row in rows) {
        row.controller.dispose();
      }
    }

    return result;
  }

  // ============================================================
  // MÉTODOS DE PAGO
  // ============================================================

  Widget _paymentMethodDropdown(
    _PaymentRow row,
    List<String> methods,
    StateSetter setDialogState,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: row.method,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Forma de pago',
      ),
      items: methods
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
        if (value == null) {
          return;
        }

        setDialogState(() {
          row.method = value;
        });
      },
    );
  }

  Widget _paymentAmountField(
    _PaymentRow row,
    StateSetter setDialogState,
  ) {
    return TextField(
      controller: row.controller,
      keyboardType:
          const TextInputType.numberWithOptions(
        decimal: true,
      ),
      decoration:
          const InputDecoration(
        labelText: 'Cantidad',
      ),
      onChanged: (_) {
        setDialogState(() {});
      },
    );
  }

  double _parseMoney(String value) {
    final normalized =
        value
            .replaceAll(
              ',',
              '',
            )
            .trim();

    return double.tryParse(
          normalized,
        ) ??
        0.0;
  }

  // ============================================================
  // RESUMEN DE PAGO
  // ============================================================

  List<Widget> _buildPaymentSummary(
    List<_PaymentRow> rows,
  ) {
    final entries = rows
        .map(
          (row) => PaymentEntry(
            method: row.method,
            amount: _parseMoney(
              row.controller.text,
            ),
          ),
        )
        .toList();

    final breakdown =
        PaymentBreakdown(
      total: _total,
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

    return [
      _summaryRow(
        'Monto a cobrar:',
        '\$${_total.toStringAsFixed(2)}',
      ),

      const SizedBox(
        height: 8,
      ),

      _summaryRow(
        'Total cobrado:',
        '\$${totalCollected.toStringAsFixed(2)}',
      ),

      const SizedBox(
        height: 8,
      ),

      const Divider(
        height: 1,
      ),

      const SizedBox(
        height: 8,
      ),

      if (cashAmount > 0) ...[
        _summaryRow(
          'Efectivo:',
          '\$${cashAmount.toStringAsFixed(2)}',
          small: true,
        ),
        const SizedBox(
          height: 6,
        ),
      ],

      if (entries
          .where(
            (e) =>
                e.method != 'Efectivo' &&
                e.amount > 0,
          )
          .isNotEmpty) ...[
        Column(
          children: entries
              .where(
                (e) =>
                    e.method !=
                        'Efectivo' &&
                    e.amount > 0,
              )
              .map(
                (entry) => Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 6,
                  ),
                  child: _summaryRow(
                    '${entry.method}:',
                    '\$${entry.amount.toStringAsFixed(2)}',
                    small: true,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(
          height: 6,
        ),
      ],

      const Divider(
        height: 1,
      ),

      const SizedBox(
        height: 8,
      ),

      if (totalCollected > _total)
        if (cashAmount > 0 &&
            entries.any(
              (e) =>
                  e.method == 'Efectivo' &&
                  e.amount > 0,
            ))
          _buildSuccessBox(
            'Cambio (efectivo):',
            '\$${change.toStringAsFixed(2)}',
          )
        else
          _buildWarningBox(
            '\$${excess.toStringAsFixed(2)}',
          )
      else if (totalCollected < _total)
        _buildErrorBox(
          '\$${shortfall.toStringAsFixed(2)}',
        )
      else
        _buildExactPaymentBox(),
    ];
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool small = false,
  }) {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
                theme.textTheme.bodySmall
                    ?.copyWith(
              color:
                  colors.onSurfaceVariant,
              fontSize:
                  small ? 11 : 12,
            ),
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        Text(
          value,
          style:
              theme.textTheme.bodyMedium
                  ?.copyWith(
            color:
                colors.onSurface,
            fontSize:
                small ? 11 : null,
            fontWeight:
                FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessBox(
    String label,
    String value,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(8),
      decoration:
          BoxDecoration(
        color:
            colors.primaryContainer,
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                    color: colors
                        .onPrimaryContainer,
                    fontWeight:
                        FontWeight.w600,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                  color: colors
                      .onPrimaryContainer,
                  fontWeight:
                      FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildExactPaymentBox() {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(8),
      decoration:
          BoxDecoration(
        color:
            colors.primaryContainer,
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Cobro exacto',
            style:
                Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: colors
                          .onPrimaryContainer,
                      fontWeight:
                          FontWeight.w600,
                    ),
          ),
          Icon(
            Icons.check_circle,
            color:
                colors.primary,
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBox(
    String value,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    final warningColor =
        colors.tertiary;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(10),
      decoration:
          BoxDecoration(
        color:
            warningColor.withAlpha(26),
        borderRadius:
            BorderRadius.circular(6),
        border:
            Border.all(
          color:
              warningColor.withAlpha(
            100,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Los pagos sin efectivo deben cubrir el importe exacto.',
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color:
                            warningColor,
                        fontWeight:
                            FontWeight.w600,
                      ),
            ),
          ),
          const SizedBox(
            width: 8,
          ),
          Text(
            value,
            style:
                Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color:
                          warningColor,
                      fontWeight:
                          FontWeight.bold,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(
    String value,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(8),
      decoration:
          BoxDecoration(
        color:
            colors.errorContainer,
        borderRadius:
            BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Falta por cobrar:',
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color:
                            colors.onErrorContainer,
                        fontWeight:
                            FontWeight.w600,
                      ),
            ),
          ),
          Text(
            value,
            style:
                Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color:
                          colors.onErrorContainer,
                      fontWeight:
                          FontWeight.bold,
                    ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VENTAS PENDIENTES
  // ============================================================

  Future<void> _showPendingSales() async {
    final sales =
        (await _db.getTodaySales())
            .where(
              (sale) =>
                  sale['status'] ==
                  'pending',
            )
            .toList();

    if (!mounted) {
      return;
    }

    final colors =
        Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height:
                MediaQuery.of(sheetContext)
                        .size
                        .height *
                    .75,
            child: ListView(
              padding:
                  const EdgeInsets.all(16),
              children: [
                Text(
                  'Ventas pendientes',
                  style:
                      Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
                const SizedBox(
                  height: 8,
                ),
                if (sales.isEmpty)
                  const ListTile(
                    title: Text(
                      'No hay ventas pendientes.',
                    ),
                  ),
                ...sales.map(
                  (sale) {
                    final id =
                        int.tryParse(
                              '${sale['id']}',
                            ) ??
                            0;

                    final total =
                        sale['total']
                                is num
                            ? (sale['total']
                                    as num)
                                .toDouble()
                            : 0.0;

                    return Card(
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading:
                            CircleAvatar(
                          backgroundColor:
                              colors
                                  .primaryContainer,
                          foregroundColor:
                              colors
                                  .onPrimaryContainer,
                          child:
                              const Icon(
                            Icons
                                .receipt_long_outlined,
                          ),
                        ),
                        title: Text(
                          'Venta #$id — \$${total.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                        ),
                        subtitle:
                            Text(
                          sale['mesa_nombre'] ==
                                  null
                              ? 'Aún no pagada'
                              : 'Mesa: ${sale['mesa_nombre']}',
                        ),
                        trailing:
                            IconButton(
                          tooltip:
                              'Eliminar pendiente',
                          icon:
                              const Icon(
                            Icons
                                .delete_outline,
                          ),
                          onPressed:
                              () async {
                            await _db
                                .deletePendingSale(
                              id,
                            );

                            if (sheetContext
                                .mounted) {
                              Navigator.of(
                                sheetContext,
                              ).pop();
                            }

                            await _loadProducts();
                          },
                        ),
                        onTap:
                            () async {
                          final items =
                              await _db
                                  .getSaleItemsBySaleId(
                            id,
                          );

                          final cart =
                              <CartItem>[];

                          for (final item
                              in items) {
                            Product? product;

                            for (final candidate
                                in _products) {
                              if (candidate
                                      .id ==
                                  item[
                                      'product_id']) {
                                product =
                                    candidate;
                                break;
                              }
                            }

                            if (product ==
                                null) {
                              continue;
                            }

                            cart.add(
                              CartItem(
                                product:
                                    product,
                                quantity:
                                    (item['quantity']
                                            as num)
                                        .toInt(),
                              ),
                            );
                          }

                          if (!mounted) {
                            return;
                          }

                          _setCart(
                            cart,
                          );

                          setState(() {
                            _pendingSaleId =
                                id;

                            _selectedTableId =
                                sale['mesa_id']
                                    as int?;

                            _selectedTableName =
                                sale[
                                      'mesa_nombre']
                                  ?.toString();
                          });

                          if (sheetContext
                              .mounted) {
                            Navigator.of(
                              sheetContext,
                            ).pop();
                          }
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // OPERACIÓN
  // ============================================================

  Future<void> _openOperation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const OperationScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadOperationState();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    if (_isLoading) {
      return Material(
        color: colors.surface,
        child: const Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    return Material(
      color: colors.surface,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          return CustomScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior
                    .onDrag,
            slivers: [
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(
                  12,
                  10,
                  12,
                  0,
                ),
                sliver:
                    SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (_cajasActivas)
                        Card(
                          margin:
                              EdgeInsets.zero,
                          child:
                              ListTile(
                            contentPadding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal:
                                  12,
                              vertical: 4,
                            ),
                            leading: Icon(
                              _cajaAbierta
                                  ? Icons
                                      .lock_open_outlined
                                  : Icons
                                      .lock_outline,
                              color:
                                  colors.primary,
                            ),
                            title: Text(
                              _cajaAbierta
                                  ? 'Caja abierta'
                                  : 'Caja pendiente de apertura',
                              maxLines: 1,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                            ),
                            subtitle:
                                Text(
                              _mesasActivas
                                  ? 'Mesas activas para esta empresa.'
                                  : 'Mesas no activas para esta empresa.',
                              maxLines: 2,
                              overflow:
                                  TextOverflow
                                      .ellipsis,
                            ),
                            trailing: _mesasActivas
                                ? Icon(
                                    Icons
                                        .table_restaurant_outlined,
                                    color:
                                        colors.primary,
                                  )
                                : null,
                            onTap:
                                _openOperation,
                          ),
                        ),

                      if (_cajasActivas)
                        const SizedBox(
                          height: 10,
                        ),

                      if (_mesasActivas)
                        DropdownButtonFormField<int?>(
                          initialValue:
                              _selectedTableId,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Mesa para la venta pendiente',
                          ),
                          items: [
                            const DropdownMenuItem<
                                int?>(
                              value: null,
                              child:
                                  Text(
                                'Sin mesa',
                              ),
                            ),
                            ..._tables
                                .where(
                              (table) =>
                                  table['activo'] !=
                                      false &&
                                  (
                                    table['estado'] ==
                                            'libre' ||
                                        table['id'] ==
                                            _selectedTableId
                                  ),
                            )
                                .map(
                              (table) {
                                return DropdownMenuItem<
                                    int?>(
                                  value:
                                      (table['id']
                                              as num)
                                          .toInt(),
                                  child:
                                      Text(
                                    '${table['nombre']} (${table['estado'] ?? 'libre'})',
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                  ),
                                );
                              },
                            ),
                          ],
                          onChanged:
                              (tableId) {
                            Map<String,
                                dynamic>?
                                table;

                            for (final item
                                in _tables) {
                              if (item[
                                      'id'] ==
                                  tableId) {
                                table =
                                    item;
                                break;
                              }
                            }

                            setState(() {
                              _selectedTableId =
                                  tableId;

                              _selectedTableName =
                                  table?[
                                          'nombre']
                                      ?.toString();
                            });
                          },
                        ),

                      if (_mesasActivas)
                        const SizedBox(
                          height: 10,
                        ),

                      _buildSearch(),

                      const SizedBox(
                        height: 12,
                      ),

                      _buildMetrics(
                        constraints,
                      ),

                      const SizedBox(
                        height: 16,
                      ),

                      Align(
                        alignment:
                            Alignment.centerLeft,
                        child: Text(
                          'Productos',
                          style: theme
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: colors
                                    .onSurface,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),
                    ],
                  ),
                ),
              ),

              if (_filteredProducts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .all(30),
                      child: Column(
                        mainAxisSize:
                            MainAxisSize
                                .min,
                        children: [
                          Icon(
                            Icons
                                .inventory_2_outlined,
                            size: 48,
                            color: colors
                                .onSurfaceVariant,
                          ),
                          const SizedBox(
                            height: 12,
                          ),
                          Text(
                            'No se encontraron productos.',
                            textAlign:
                                TextAlign.center,
                            style: theme
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colors
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    100,
                  ),
                  sliver:
                      SliverLayoutBuilder(
                    builder: (
                      context,
                      sliverConstraints,
                    ) {
                      final width =
                          sliverConstraints
                              .crossAxisExtent;

                      final columns =
                          width >= 1000
                              ? 3
                              : width >= 650
                                  ? 2
                                  : 1;

                      if (columns == 1) {
                        return SliverList(
                          delegate:
                              SliverChildBuilderDelegate(
                            (
                              context,
                              index,
                            ) {
                              final product =
                                  _filteredProducts[
                                      index];

                              return Padding(
                                padding:
                                    const EdgeInsets
                                        .only(
                                  bottom:
                                      10,
                                ),
                                child:
                                    _buildProductCard(
                                  product,
                                ),
                              );
                            },
                            childCount:
                                _filteredProducts
                                    .length,
                          ),
                        );
                      }

                      return SliverGrid(
                        delegate:
                            SliverChildBuilderDelegate(
                          (
                            context,
                            index,
                          ) {
                            return _buildProductCard(
                              _filteredProducts[
                                  index],
                            );
                          },
                          childCount:
                              _filteredProducts
                                  .length,
                        ),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              columns,
                          crossAxisSpacing:
                              12,
                          mainAxisSpacing:
                              12,
                          childAspectRatio:
                              columns == 2
                                  ? 2.1
                                  : 2.0,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // PRODUCTOS FILTRADOS
  // ============================================================

  List<Product> get _filteredProducts {
    final query =
        _searchController.text
            .trim()
            .toLowerCase();

    if (query.isEmpty) {
      return _products;
    }

    return _products.where(
      (product) {
        return product.name
                .toLowerCase()
                .contains(query) ||
            product.code
                .toLowerCase()
                .contains(query);
      },
    ).toList();
  }

  // ============================================================
  // BUSCADOR
  // ============================================================

  Widget _buildSearch() {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller:
                _searchController,
            decoration:
                InputDecoration(
              hintText:
                  'Buscar producto por nombre o código',
              prefixIcon:
                  Icon(
                Icons.search,
                color:
                    colors.primary,
              ),
            ),
            onChanged: (_) {
              setState(() {});
            },
          ),
        ),
        const SizedBox(
          width: 8,
        ),
        DecoratedBox(
          decoration:
              BoxDecoration(
            color:
                colors.primaryContainer,
            borderRadius:
                BorderRadius.circular(
              14,
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(
              12,
            ),
            child: Icon(
              Icons.filter_list,
              color:
                  colors.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MÉTRICAS
  // ============================================================

  Widget _buildMetrics(
    BoxConstraints constraints,
  ) {
    final width =
        constraints.maxWidth;

    int columns;

    if (width < 500) {
      columns = 1;
    } else if (width < 800) {
      columns = 2;
    } else {
      columns = 3;
    }

    final colors =
        Theme.of(context).colorScheme;

    final metrics = [
      _MetricCard(
        label: 'Ventas del día',
        value:
            '$_todaySales',
        color:
            colors.primary,
      ),
      _MetricCard(
        label: 'Pendientes',
        value:
            '$_pendingSales',
        color:
            colors.tertiary,
      ),
      _MetricCard(
        label: 'Canceladas',
        value:
            '$_cancelledSales',
        color:
            colors.error,
      ),
    ];

    return GridView.count(
      crossAxisCount:
          columns,
      crossAxisSpacing:
          10,
      mainAxisSpacing:
          10,
      childAspectRatio:
          columns == 1
              ? 4.2
              : 2.4,
      shrinkWrap:
          true,
      physics:
          const NeverScrollableScrollPhysics(),
      children:
          metrics,
    );
  }

  // ============================================================
  // TARJETA PRODUCTO
  // ============================================================

  Widget _buildProductCard(
    Product product,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    return Card(
      margin:
          EdgeInsets.zero,
      clipBehavior:
          Clip.antiAlias,
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          10,
        ),
        child:
            LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final compact =
                constraints.maxWidth <
                    340;

            if (compact) {
              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      _productCode(
                        product,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child:
                            _productInformation(
                          product,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 10,
                  ),
                  _productBottomActions(
                    product,
                    fullWidth:
                        true,
                  ),
                ],
              );
            }

            return Row(
              children: [
                _productCode(
                  product,
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child:
                      _productInformation(
                    product,
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                _productBottomActions(
                  product,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _productCode(
    Product product,
  ) {
    final colors =
        Theme.of(context).colorScheme;

    return Container(
      width: 52,
      height: 52,
      decoration:
          BoxDecoration(
        color:
            colors.primaryContainer,
        borderRadius:
            BorderRadius.circular(
          14,
        ),
      ),
      child: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            4,
          ),
          child: FittedBox(
            fit:
                BoxFit.scaleDown,
            child: Text(
              product.code,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(
                    color: colors
                        .onPrimaryContainer,
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productInformation(
    Product product,
  ) {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    final hasStock =
        product.stock > 0;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          maxLines: 2,
          overflow:
              TextOverflow.ellipsis,
          style: theme
              .textTheme
              .titleMedium
              ?.copyWith(
                color:
                    colors.onSurface,
                fontWeight:
                    FontWeight.w700,
              ),
        ),
        const SizedBox(
          height: 6,
        ),
        Container(
          padding:
              const EdgeInsets
                  .symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration:
              BoxDecoration(
            color: hasStock
                ? colors
                    .primaryContainer
                : colors
                    .errorContainer,
            borderRadius:
                BorderRadius.circular(
              999,
            ),
          ),
          child: Text(
            'Stock: ${product.stock.toStringAsFixed(0)}',
            style: theme
                .textTheme
                .labelSmall
                ?.copyWith(
                  color: hasStock
                      ? colors
                          .onPrimaryContainer
                      : colors
                          .onErrorContainer,
                  fontWeight:
                      FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _productBottomActions(
    Product product, {
    bool fullWidth = false,
  }) {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    final price = Text(
      '\$${product.price.toStringAsFixed(2)}',
      style: theme
          .textTheme
          .titleLarge
          ?.copyWith(
            color:
                colors.onSurface,
            fontWeight:
                FontWeight.w800,
          ),
    );

    final button =
        ElevatedButton(
      onPressed:
          product.stock > 0
              ? () => _addToCart(
                    product,
                  )
              : null,
      child:
          const Text(
        'Agregar',
      ),
    );

    if (fullWidth) {
      return Row(
        children: [
          Expanded(
            child: price,
          ),
          const SizedBox(
            width: 8,
          ),
          button,
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        FittedBox(
          child: price,
        ),
        const SizedBox(
          height: 8,
        ),
        button,
      ],
    );
  }
}

// ============================================================
// MODELO DE FILA DE PAGO
// ============================================================

class _PaymentRow {
  _PaymentRow({
    required this.method,
    required this.controller,
  });

  String method;

  final TextEditingController
      controller;
}

// ============================================================
// TARJETA DE MÉTRICA
// ============================================================

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
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);
    final colors =
        theme.colorScheme;

    return Card(
      child:
          Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style: theme
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                          color: colors
                              .onSurfaceVariant,
                          fontWeight:
                              FontWeight.w600,
                        ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    value,
                    style: theme
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          color: color,
                          fontWeight:
                              FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(
                color:
                    color.withAlpha(
                  25,
                ),
                shape:
                    BoxShape.circle,
              ),
              child: Icon(
                Icons
                    .trending_up_rounded,
                color:
                    color,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}