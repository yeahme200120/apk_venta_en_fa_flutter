import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/product.dart';
import '../../core/models/sale_model.dart';
import '../../core/payments/payment_breakdown.dart';
import 'cart_screen.dart';
import '../ventas/sale_detail_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PaymentRow {
  _PaymentRow({required this.method, required this.controller});

  String method;
  final TextEditingController controller;
}

class _PosScreenState extends State<PosScreen> {
  final LocalDb _db = LocalDb();
  final TextEditingController _searchController = TextEditingController();

  List<Product> _products = [];
  final List<CartItem> _cart = [];
  bool _isLoading = true;
  int _todaySales = 0;
  int _pendingSales = 0;
  int _cancelledSales = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final items = await _db.getProducts();
    final sales = await _db.getTodaySales();
    setState(() {
      _products = items.map(Product.fromMap).toList();
      _todaySales = sales.length;
      _pendingSales = sales.where((sale) => sale['sync_status'] != 'synced').length;
      _cancelledSales = sales.where((sale) => sale['status'] == 'cancelled').length;
      _isLoading = false;
    });
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _products;

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
    }).toList();
  }

  void _addToCart(Product product) {
    final existingIndex = _cart.indexWhere((item) => item.product.id == product.id);

    setState(() {
      if (existingIndex >= 0) {
        final existing = _cart[existingIndex];
        _cart[existingIndex] = CartItem(
          product: existing.product,
          quantity: existing.quantity + 1,
        );
      } else {
        _cart.add(CartItem(product: product, quantity: 1));
      }
    });
  }

  void _removeFromCart(int productId) {
    setState(() {
      _cart.removeWhere((item) => item.product.id == productId);
    });
  }

  void _changeQuantity(int productId, int delta) {
    setState(() {
      final index = _cart.indexWhere((item) => item.product.id == productId);
      if (index == -1) return;

      final newQty = _cart[index].quantity + delta;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index] = CartItem(
          product: _cart[index].product,
          quantity: newQty,
        );
      }
    });
  }

  Future<void> _openCart() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CartScreen(
          items: _cart,
          onQuantityChanged: _changeQuantity,
          onRemove: _removeFromCart,
          onClear: () => setState(_cart.clear),
          onCheckout: _confirmSale,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  double get _total => _cart.fold(
        0,
        (previousValue, item) => previousValue + item.subtotal,
      );

  double _parseMoney(String value) {
    final normalized = value.replaceAll(',', '').trim();
    return double.tryParse(normalized) ?? 0.0;
  }

  List<Widget> _buildPaymentSummary(List<_PaymentRow> rows) {
    final entries = rows
        .map(
          (row) => PaymentEntry(
            method: row.method,
            amount: _parseMoney(row.controller.text),
          ),
        )
        .toList();

    final breakdown = PaymentBreakdown(total: _total, payments: entries);
    final totalCollected = breakdown.totalCollected;
    final cashAmount = breakdown.cashAmount;
    final change = breakdown.change;
    final excess = breakdown.excess;
    final shortfall = breakdown.shortfall;

    final widgets = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Monto a cobrar:', style: TextStyle(fontSize: 12, color: Colors.black54)),
          Text('\$${_total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total cobrado:', style: TextStyle(fontSize: 12, color: Colors.black54)),
          Text('\$${totalCollected.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 8),
      const Divider(height: 1),
      const SizedBox(height: 8),
      if (cashAmount > 0) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Efectivo:', style: TextStyle(fontSize: 11, color: Colors.black54)),
            Text('\$${cashAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 6),
      ],
      if (entries.where((e) => e.method != 'Efectivo').isNotEmpty) ...[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries
              .where((e) => e.method != 'Efectivo' && e.amount > 0)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${entry.method}:', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      Text('\$${entry.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
      ],
      const Divider(height: 1),
      const SizedBox(height: 8),
      if (totalCollected > _total) ...[
        if (cashAmount > 0 && entries.where((e) => e.method == 'Efectivo').isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF9AC53B).withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cambio (efectivo):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2D6A1E))),
                Text('\$${change.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D6A1E))),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(26),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text('Los pagos sin efectivo deben cubrir el importe exacto.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange)),
                    ),
                    Text('\$${excess.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ] else if (totalCollected < _total) ...[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Falta por cobrar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)),
              Text('\$${shortfall.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
            ],
          ),
        ),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF9AC53B).withAlpha(20),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Cobro exacto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2D6A1E))),
              Icon(Icons.check_circle, color: Color(0xFF2D6A1E), size: 18),
            ],
          ),
        ),
      ],
    ];

    return widgets;
  }

  Future<void> _confirmSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos al carrito antes de confirmar.')),
      );
      return;
    }

    final paymentData = await _showPaymentDialog();
    if (paymentData == null) return;

    final uuid = 'sale_${DateTime.now().millisecondsSinceEpoch}';
    final saleItems = _cart.map((item) {
      return {
        'product_id': item.product.id,
        'name': item.product.name,
        'quantity': item.quantity,
        'unit_price': item.product.price,
        'total': item.subtotal,
      };
    }).toList();

    final payments = (paymentData['payments'] as List<Map<String, dynamic>>?) ?? const [];
    final paymentBreakdown = PaymentBreakdown(
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

    final cashAmount = paymentBreakdown.cashAmount;
    final change = paymentBreakdown.change;

    await _db.saveSale(
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

    final generatedSaleId = await _db.getTodaySales();
    if (generatedSaleId.isNotEmpty && mounted) {
      final sale = generatedSaleId.first;
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

    if (!mounted) return;

    setState(() {
      _cart.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Venta pagada y guardada para sincronización. Cambio: \$${change.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showPaymentDialog() async {
    const methods = ['Efectivo', 'Tarjeta', 'Transferencia', 'Cheque'];
    final rows = <_PaymentRow>[
      _PaymentRow(
        method: 'Efectivo',
        controller: TextEditingController(text: _total.toStringAsFixed(2)),
      ),
    ];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cobro y cambio'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9AC53B).withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Monto a cobrar', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            Text(
                              '\$${_total.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...List.generate(rows.length, (index) {
                        final row = rows[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButton<String>(
                                    value: row.method,
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    items: methods
                                        .map(
                                          (method) => DropdownMenuItem<String>(
                                            value: method,
                                            child: Text(method),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setDialogState(() {
                                        row.method = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: row.controller,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Cantidad',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: rows.length > 1
                                    ? () {
                                        setDialogState(() {
                                          rows.removeAt(index);
                                        });
                                      }
                                    : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () {
                          rows.add(
                            _PaymentRow(
                              method: 'Efectivo',
                              controller: TextEditingController(text: '0.00'),
                            ),
                          );
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Agregar tipo de pago'),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resumen de cobro',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            ..._buildPaymentSummary(rows),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final entries = rows
                        .map(
                          (row) => PaymentEntry(
                            method: row.method,
                            amount: _parseMoney(row.controller.text),
                          ),
                        )
                        .where((entry) => entry.amount > 0)
                        .toList();

                    if (entries.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Debes indicar al menos un pago.')),
                      );
                      return;
                    }

                    final breakdown = PaymentBreakdown(total: _total, payments: entries);
                    if (breakdown.totalCollected < _total) {
                      final falta = (breakdown.shortfall).toStringAsFixed(2);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Falta por cobrar: \$$falta')),
                      );
                      return;
                    }

                    final hasNonCashOverage = entries.any((entry) => entry.method != 'Efectivo') &&
                        breakdown.totalCollected > _total;
                    if (hasNonCashOverage) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tarjeta, transferencia y cheque deben cubrir exactamente el total.')),
                      );
                      return;
                    }

                    Navigator.of(dialogContext).pop({
                      'payments': entries
                          .map((entry) => {'method': entry.method, 'amount': entry.amount})
                          .toList(),
                    });
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Guardar cobro'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Widget _buildProductCard(Product product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF9AC53B).withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  product.code,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2B3A1E),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1F2A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: product.stock > 0
                          ? const Color(0xFF9AC53B).withAlpha(23)
                          : Colors.red.withAlpha(20),
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
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2A1A),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _addToCart(product),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9AC53B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

  // Kept as a local fallback for layouts that embed the cart.
  // ignore: unused_element
  Widget _buildCartSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F2),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _cart.isEmpty ? 'Carrito vacío' : 'Carrito (${_cart.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              Text(
                '\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2A1A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_cart.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Agrega productos para comenzar la venta',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _cart.length,
                itemBuilder: (context, index) {
                  final item = _cart[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(
                                '\$${item.product.price.toStringAsFixed(2)} c/u',
                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _changeQuantity(item.product.id, -1),
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                            Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              onPressed: () => _changeQuantity(item.product.id, 1),
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => _removeFromCart(item.product.id),
                          icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 18),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cart.isEmpty ? null : () => setState(() => _cart.clear()),
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Vaciar'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF9AC53B)),
                    foregroundColor: const Color(0xFF1F2A1A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _cart.isEmpty ? null : _confirmSale,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Cobrar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9AC53B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF3F6EE),
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
            const SizedBox(width: 12),
            const Text(
              'Caja',
              style: TextStyle(
                color: Color(0xFF1F2A1A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF9AC53B),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _cart.isEmpty ? 'Sin venta' : 'Total ${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2A1A),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.filter_list, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Ventas del día',
                          value: '$_todaySales',
                          color: const Color(0xFF9AC53B),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          label: 'Pendientes',
                          value: '$_pendingSales',
                          color: const Color(0xFFFFB703),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          label: 'Canceladas',
                          value: '$_cancelledSales',
                          color: const Color(0xFF1F9D8A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) => _buildProductCard(_filteredProducts[index]),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCart,
        backgroundColor: const Color(0xFF9AC53B),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.shopping_cart_outlined),
        label: Text('Carrito (${_cart.length})'),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
