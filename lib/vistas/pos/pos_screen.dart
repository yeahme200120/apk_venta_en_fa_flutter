import 'dart:async';

import 'package:flutter/material.dart';

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
  const PosScreen({super.key, this.onCartChanged});

  final ValueChanged<int>? onCartChanged;

  @override
  PosScreenState createState() => PosScreenState();
}

class PosScreenState extends State<PosScreen> {
  final LocalDb _db = LocalDb();
  final PrinterService _printerService = PrinterService();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<CartItem>> _cartNotifier =
      ValueNotifier<List<CartItem>>([]);

  StreamSubscription<void>? _salesChangesSubscription;
  bool _refreshing = false;
  bool _syncing = false;
  bool _refreshQueued = false;

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
    _printerService.dispose();
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
        SnackBar(content: Text('No fue posible actualizar la caja: $error')),
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
        SnackBar(content: Text('No fue posible actualizar la caja: $error')),
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

  double get _total =>
      _cartNotifier.value.fold(0, (sum, item) => sum + item.subtotal);

  void _addToCart(Product product) {
    final current = List<CartItem>.from(_cartNotifier.value);

    final index = current.indexWhere((item) => item.product.id == product.id);

    if (index >= 0) {
      final existing = current[index];

      current[index] = CartItem(
        product: existing.product,
        quantity: existing.quantity + 1,
      );
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
      current[index] = CartItem(
        product: current[index].product,
        quantity: newQty,
      );
    }

    _setCart(current);
  }

  void _removeFromCart(int productId) {
    final current = List<CartItem>.from(_cartNotifier.value);

    current.removeWhere((item) => item.product.id == productId);

    _setCart(current);
  }

  void _clearCart() {
    _setCart([]);
  }

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

    if (mounted) {
      setState(() {});
    }
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
            content: Text(
              'Un cajero debe abrir la caja antes de registrar o cobrar ventas.',
            ),
          ),
        );
      }

      return false;
    }

    return true;
  }

  // ============================================================
  // DIÁLOGO DE IMPRESORA
  // ============================================================

  Future<bool> _showPrinterConnectionDialog() async {
    try {
      var printers = await _printerService.pairedBluetoothPrinters();

      if (!mounted) {
        return false;
      }

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          PrinterDevice? selectedPrinter;
          bool loading = false;
          String? errorMessage;

          Future<void> refreshPrinters(StateSetter setDialogState) async {
            setDialogState(() {
              loading = true;
              errorMessage = null;
            });

            try {
              final updated = await _printerService.pairedBluetoothPrinters();

              if (!dialogContext.mounted) {
                return;
              }

              setDialogState(() {
                printers = updated;

                if (selectedPrinter != null &&
                    !updated.any(
                      (printer) => printer.address == selectedPrinter!.address,
                    )) {
                  selectedPrinter = null;
                }
              });
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }

              setDialogState(() {
                errorMessage =
                    'No fue posible obtener las impresoras Bluetooth.';
              });

              debugPrint('❌ Error actualizando impresoras: $error');
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() {
                  loading = false;
                });
              }
            }
          }

          Future<void> connectSelected(StateSetter setDialogState) async {
            if (selectedPrinter == null) {
              setDialogState(() {
                errorMessage = 'Selecciona una impresora antes de continuar.';
              });

              return;
            }

            setDialogState(() {
              loading = true;
              errorMessage = null;
            });

            try {
              final connected = await _printerService.selectAndConnectPrinter(
                selectedPrinter!.address,
              );

              if (!dialogContext.mounted) {
                return;
              }

              if (connected) {
                Navigator.of(dialogContext).pop(true);
                return;
              }

              setDialogState(() {
                errorMessage =
                    'No fue posible conectar con la impresora '
                    '${selectedPrinter!.displayName}.';
              });
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }

              setDialogState(() {
                errorMessage = 'Error al conectar con la impresora: $error';
              });
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() {
                  loading = false;
                });
              }
            }
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.print_outlined),
                    SizedBox(width: 10),
                    Expanded(child: Text('Impresora de tickets')),
                  ],
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'No hay una impresora de tickets conectada.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Selecciona una impresora Bluetooth emparejada '
                          'para imprimir el ticket automáticamente.',
                        ),
                        const SizedBox(height: 20),

                        if (loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (printers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.bluetooth_disabled, size: 36),
                                SizedBox(height: 10),
                                Text(
                                  'No hay impresoras Bluetooth emparejadas.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Empareja la impresora desde los ajustes '
                                  'Bluetooth de Android y después actualiza '
                                  'esta lista.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: selectedPrinter?.address,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Impresora',
                              prefixIcon: Icon(Icons.print),
                              border: OutlineInputBorder(),
                            ),
                            items: printers.map((printer) {
                              return DropdownMenuItem<String>(
                                value: printer.address,
                                child: Text(
                                  printer.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: loading
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    final printer = printers.firstWhere(
                                      (item) => item.address == value,
                                    );

                                    setDialogState(() {
                                      selectedPrinter = printer;
                                      errorMessage = null;
                                    });
                                  },
                          ),

                        if (errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),

                        OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () => refreshPrinters(setDialogState),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizar impresoras'),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop(false);
                          },
                    child: const Text('Continuar sin imprimir'),
                  ),
                  FilledButton.icon(
                    onPressed: loading || selectedPrinter == null
                        ? null
                        : () => connectSelected(setDialogState),
                    icon: const Icon(Icons.bluetooth_connected),
                    label: const Text('Conectar e imprimir'),
                  ),
                ],
              );
            },
          );
        },
      );

      return result ?? false;
    } catch (error, stackTrace) {
      debugPrint('❌ Error mostrando diálogo de impresora: $error');
      debugPrint('$stackTrace');

      return false;
    }
  }

  // ============================================================
  // IMPRESIÓN AUTOMÁTICA
  // ============================================================

  Future<bool> _printSaleAutomatically({
    required int saleId,
    required List<Map<String, dynamic>> saleItems,
    required List<Map<String, dynamic>> payments,
    required double total,
    required double cashReceived,
    required double change,
  }) async {
    debugPrint('══════════════════════════════════════');
    debugPrint('🖨️ INICIO IMPRESIÓN AUTOMÁTICA');
    debugPrint('🧾 Venta: $saleId');
    debugPrint('💰 Total: $total');
    debugPrint('💵 Efectivo recibido: $cashReceived');
    debugPrint('🔄 Cambio: $change');
    debugPrint('💳 Pagos: $payments');

    try {
      var selectedPrinter = await _printerService.selectedPrinter();

      debugPrint(
        '🖨️ Impresora seleccionada: '
        '${selectedPrinter?.displayName ?? "NINGUNA"}',
      );

      // ========================================================
      // CASO 1: NO HAY IMPRESORA SELECCIONADA
      // ========================================================

      if (selectedPrinter == null) {
        debugPrint('⚠️ No hay impresora seleccionada.');

        final shouldPrint = await _showPrinterConnectionDialog();

        if (!shouldPrint) {
          debugPrint('🖨️ Usuario decidió continuar sin imprimir.');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Venta guardada sin imprimir ticket.'),
                duration: Duration(seconds: 3),
              ),
            );
          }

          return false;
        }

        selectedPrinter = await _printerService.selectedPrinter();

        if (selectedPrinter == null) {
          debugPrint(
            '❌ No quedó una impresora seleccionada '
            'después del diálogo.',
          );

          return false;
        }
      }

      // ========================================================
      // CASO 2: CONECTAR IMPRESORA SELECCIONADA
      // ========================================================

      var connected = await _printerService.ensureBluetoothConnection();

      debugPrint('🔌 Bluetooth conectado: $connected');

      // ========================================================
      // CASO 3: NO SE PUDO CONECTAR
      // ========================================================

      if (!connected) {
        debugPrint(
          '⚠️ No fue posible conectar la impresora '
          '${selectedPrinter.displayName} '
          '(${selectedPrinter.address}).',
        );

        final shouldPrint = await _showPrinterConnectionDialog();

        if (!shouldPrint) {
          debugPrint('🖨️ Usuario decidió continuar sin imprimir.');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Venta guardada sin imprimir ticket.'),
                duration: Duration(seconds: 3),
              ),
            );
          }

          return false;
        }

        // El diálogo puede haber seleccionado/cambiado la impresora.
        selectedPrinter = await _printerService.selectedPrinter();

        if (selectedPrinter == null) {
          debugPrint('❌ No hay impresora seleccionada después del diálogo.');

          return false;
        }

        connected = await _printerService.ensureBluetoothConnection();

        debugPrint(
          '🔌 Resultado de conexión después del diálogo: '
          '$connected',
        );

        if (!connected) {
          debugPrint('❌ La impresora sigue sin conexión.');

          return false;
        }
      }

      // ========================================================
      // CASO 4: IMPRIMIR
      // ========================================================

      final saleForPrint = <String, dynamic>{
        'id': saleId,
        'folio': saleId.toString(),
        'fecha': DateTime.now().toIso8601String(),
        'items': saleItems,
        'total': total,
        'payments': payments,
        'cashReceived': cashReceived,
        'changeDue': change,
      };

      debugPrint('✅ Impresora conectada.');
      debugPrint('🖨️ Enviando ticket...');

      final result = await _printerService.printSale(saleForPrint);

      debugPrint(
        '🖨️ Resultado impresión: '
        'success=${result.success}, '
        'message=${result.message}',
      );

      if (!result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Venta guardada, pero no fue posible imprimir: '
                '${result.message}',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }

        return false;
      }

      debugPrint('✅ TICKET IMPRESO CORRECTAMENTE');
      debugPrint('══════════════════════════════════════');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ticket impreso correctamente.'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (error, stackTrace) {
      debugPrint('❌ ERROR DE IMPRESIÓN: $error');
      debugPrint('$stackTrace');
      debugPrint('══════════════════════════════════════');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Venta guardada, pero ocurrió un error al imprimir: '
              '$error',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      return false;
    }
  }

  // ============================================================
  // CONFIRMAR VENTA
  // ============================================================

  Future<bool> _confirmSale() async {
    if (_cartNotifier.value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega productos al carrito antes de confirmar.'),
        ),
      );

      return false;
    }

    if (!await _canOperateSale()) {
      return false;
    }

    final paymentData = await _showPaymentDialog();

    if (paymentData == null) {
      return false;
    }

    final uuid = 'sale_${DateTime.now().millisecondsSinceEpoch}';

    final saleItems = _currentSaleItems();

    final payments =
        (paymentData['payments'] as List<Map<String, dynamic>>?) ?? const [];

    final breakdown = PaymentBreakdown(
      total: _total,
      payments: payments
          .map(
            (item) => PaymentEntry(
              method: (item['method'] ?? '').toString().trim(),
              amount: item['amount'] is num
                  ? (item['amount'] as num).toDouble()
                  : 0.0,
            ),
          )
          .where((entry) => entry.method.isNotEmpty && entry.amount > 0)
          .toList(),
    );

    final cashReceived = breakdown.cashAmount;
    final change = breakdown.change;

    // sale_payments conserva los importes APLICADOS a la venta.
    // cashReceived conserva el efectivo realmente recibido
    // y changeDue conserva el cambio entregado.
    final adjustedPayments = <Map<String, dynamic>>[];

    var remainingChange = change;

    for (final payment in payments) {
      final method = (payment['method'] ?? '').toString().trim();

      final originalAmount = payment['amount'] is num
          ? (payment['amount'] as num).toDouble()
          : 0.0;

      if (method.isEmpty || originalAmount <= 0) {
        continue;
      }

      var appliedAmount = originalAmount;

      if (method == 'Efectivo' && remainingChange > 0) {
        final deduction = remainingChange < appliedAmount
            ? remainingChange
            : appliedAmount;

        appliedAmount -= deduction;
        remainingChange -= deduction;
      }

      if (appliedAmount > 0.005) {
        adjustedPayments.add({
          'method': method,
          'amount': double.parse(appliedAmount.toStringAsFixed(2)),
        });
      }
    }

    final appliedTotal = adjustedPayments.fold<double>(0, (sum, payment) {
      final amount = payment['amount'] is num
          ? (payment['amount'] as num).toDouble()
          : 0.0;

      return sum + amount;
    });

    if ((appliedTotal - _total).abs() > 0.01) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No fue posible ajustar correctamente '
              'el pago y el cambio.',
            ),
          ),
        );
      }

      return false;
    }

    final paymentMethods = <String>[];

    for (final payment in adjustedPayments) {
      final method = payment['method']?.toString().trim() ?? '';

      if (method.isNotEmpty && !paymentMethods.contains(method)) {
        paymentMethods.add(method);
      }
    }

    final paymentMethod = paymentMethods.join(', ');

    var saleId = _pendingSaleId;

    try {
      if (saleId != null) {
        final paid = await _db.payPendingSale(
          saleId,
          payments: adjustedPayments,
          paymentMethod: paymentMethod,
          cashReceived: cashReceived,
          changeDue: change,
        );

        if (!paid) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('La venta pendiente ya no está disponible.'),
              ),
            );
          }

          return false;
        }
      } else {
        saleId = await _db.saveSale(
          uuid: uuid,
          items: saleItems,
          payments: adjustedPayments,
          total: _total,
          status: 'paid',
          syncStatus: 'pending',
          paymentMethod: paymentMethod,
          cashReceived: cashReceived,
          changeDue: change,
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message.toString())));
      }

      return false;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fue posible guardar la venta: $error')),
        );
      }

      return false;
    }

    final savedSaleId = saleId;

    if (savedSaleId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La venta se guardó, pero no se obtuvo '
              'su identificador.',
            ),
          ),
        );
      }

      return false;
    }

    // ==========================================================
    // IMPRIMIR DESPUÉS DE GUARDAR
    // ==========================================================

    final ticketPrinted = await _printSaleAutomatically(
      saleId: savedSaleId,
      saleItems: saleItems,
      payments: adjustedPayments,
      total: _total,
      cashReceived: cashReceived,
      change: change,
    );

    debugPrint('🖨️ Estado final ticketPrinted=$ticketPrinted');
    if (ticketPrinted) {
      await _db.setSalePrintTicket(savedSaleId, true);
    }

    // ==========================================================
    // OBTENER VENTA GUARDADA
    // ==========================================================

    final generatedSale = await _db.getSaleById(savedSaleId);

    if (generatedSale != null && mounted) {
      final sale = generatedSale;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            sale: SaleModel(
              id: int.tryParse('${sale['id'] ?? savedSaleId}') ?? savedSaleId,
              uuidLocal: sale['uuid_local']?.toString() ?? uuid,
              serverId: null,
              businessDate: DateTime.now().toIso8601String().substring(0, 10),
              total: sale['total'] is num
                  ? (sale['total'] as num).toDouble()
                  : _total,
              syncStatus: sale['sync_status']?.toString() ?? 'pending',
              status: sale['status']?.toString() ?? 'paid',
              items: saleItems
                  .map(
                    (item) => SaleItemModel(
                      id: 0,
                      saleId: savedSaleId,
                      productId: int.tryParse('${item['product_id']}') ?? 0,
                      name: item['name']?.toString() ?? '',
                      quantity: item['quantity'] is num
                          ? (item['quantity'] as num).toDouble()
                          : 0.0,
                      unitPrice: item['unit_price'] is num
                          ? (item['unit_price'] as num).toDouble()
                          : 0.0,
                      total: item['total'] is num
                          ? (item['total'] as num).toDouble()
                          : 0.0,
                    ),
                  )
                  .toList(),
              payments: adjustedPayments
                  .map(
                    (item) => SalePaymentModel(
                      id: 0,
                      saleId: savedSaleId,
                      method: item['method']?.toString() ?? '',
                      amount: item['amount'] is num
                          ? (item['amount'] as num).toDouble()
                          : 0.0,
                    ),
                  )
                  .toList(),
              createdAt:
                  sale['created_at']?.toString() ??
                  DateTime.now().toIso8601String(),
              updatedAt:
                  sale['updated_at']?.toString() ??
                  DateTime.now().toIso8601String(),
              changeDue: change,
            ),
          ),
        ),
      );
    }

    if (!mounted) {
      return false;
    }

    _setCart([]);

    setState(() {
      _pendingSaleId = null;
      _selectedTableId = null;
      _selectedTableName = null;
    });

    await _loadProducts();

    if (!mounted) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ticketPrinted
              ? 'Venta pagada, guardada y ticket impreso. '
                    'Cambio: \$${change.toStringAsFixed(2)}'
              : 'Venta pagada y guardada sin ticket. '
                    'Cambio: \$${change.toStringAsFixed(2)}',
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
  // ============================================================
  // OPERACIÓN
  // ============================================================

  Future<void> _openOperation() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OperationScreen()));

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
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.point_of_sale, color: colorScheme.onPrimary),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Caja',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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
                      tooltip: items.isEmpty
                          ? 'Carrito vacío'
                          : 'Abrir carrito',
                      onPressed: _openCart,
                      icon: const Icon(Icons.shopping_cart_outlined),
                    ),
                    if (items.isNotEmpty)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
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
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    leading: Icon(
                                      _cajaAbierta
                                          ? Icons.lock_open_outlined
                                          : Icons.lock_outline,
                                    ),
                                    title: Text(
                                      _cajaAbierta
                                          ? 'Caja abierta'
                                          : 'Caja pendiente de apertura',
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
                                        ? const Icon(
                                            Icons.table_restaurant_outlined,
                                          )
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
                                                  table['id'] ==
                                                      _selectedTableId),
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

                                      _selectedTableName = table?['nombre']
                                          ?.toString();
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
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
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

                              final columns = width >= 1000
                                  ? 3
                                  : width >= 650
                                  ? 2
                                  : 1;

                              if (columns == 1) {
                                return SliverList(
                                  delegate: SliverChildBuilderDelegate((
                                    context,
                                    index,
                                  ) {
                                    final product = _filteredProducts[index];

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: _buildProductCard(
                                        context,
                                        product,
                                      ),
                                    );
                                  }, childCount: _filteredProducts.length),
                                );
                              }

                              return SliverGrid(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _buildProductCard(
                                    context,
                                    _filteredProducts[index],
                                  ),
                                  childCount: _filteredProducts.length,
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: columns == 2
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
            ),
    );
  }

  // ============================================================
  // WIDGETS DE UI
  // ============================================================

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _products;
    }

    return _products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.code.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildSearch(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withAlpha(45),
              ),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar producto por nombre o código',
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.primary,
                ),
                border: InputBorder.none,
                hintStyle: const TextStyle(color: Colors.black54),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.filter_list,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMetrics(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;

    int columns;

    if (width < 500) {
      columns = 1;
    } else if (width < 800) {
      columns = 2;
    } else {
      columns = 3;
    }

    final metrics = [
      _MetricCard(
        label: 'Ventas del día',
        value: '$_todaySales',
        color: Theme.of(context).colorScheme.primary,
      ),
      _MetricCard(
        label: 'Pendientes',
        value: '$_pendingSales',
        color: Theme.of(context).colorScheme.tertiary,
      ),
      _MetricCard(
        label: 'Canceladas',
        value: '$_cancelledSales',
        color: Theme.of(context).colorScheme.secondary,
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

  Widget _buildProductCard(BuildContext context, Product product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(50),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withAlpha(18),
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
                      _productCode(context, product),
                      const SizedBox(width: 10),
                      Expanded(child: _productInformation(context, product)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _productBottomActions(context, product, fullWidth: true),
                ],
              );
            }

            return Row(
              children: [
                _productCode(context, product),
                const SizedBox(width: 12),
                Expanded(child: _productInformation(context, product)),
                const SizedBox(width: 10),
                _productBottomActions(context, product),
              ],
            );
          },
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: product.stock > 0
                ? Theme.of(context).colorScheme.primary.withAlpha(23)
                : Theme.of(context).colorScheme.error.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Stock: ${product.stock.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              color: product.stock > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _productBottomActions(
    BuildContext context,
    Product product, {
    bool fullWidth = false,
  }) {
    if (fullWidth) {
      return Row(
        children: [
          Expanded(
            child: Text(
              '\$${product.price.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _addToCart(product),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => _addToCart(product),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

// ============================================================
// DIÁLOGO DE PAGO
// ============================================================

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

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
      _createRow(method: 'Efectivo', amount: widget.total.toStringAsFixed(2)),
    );
  }

  _PaymentRowData _createRow({
    String method = 'Efectivo',
    String amount = '0.00',
  }) {
    return _PaymentRowData(
      id: _nextRowId++,
      method: method,
      controller: TextEditingController(text: amount),
    );
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

    setState(() {
      _rows.add(_createRow());
    });
  }

  void _removePaymentRow(int rowId) {
    if (!mounted || _rows.length <= 1) {
      return;
    }

    final index = _rows.indexWhere((row) => row.id == rowId);

    if (index < 0) {
      return;
    }

    final row = _rows[index];

    setState(() {
      _rows.removeAt(index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      row.controller.dispose();
    });
  }

  double _parseMoney(String value) {
    final normalized = value.replaceAll(',', '').replaceAll(r'$', '').trim();

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
        .where((entry) => entry.amount > 0)
        .toList();
  }

  void _submit() {
    if (!mounted) return;

    final entries = _entries();

    if (entries.isEmpty) {
      _showMessage('Debes indicar al menos un pago.', isError: true);
      return;
    }

    final breakdown = PaymentBreakdown(total: widget.total, payments: entries);

    if (breakdown.totalCollected + 0.005 < widget.total) {
      final falta = breakdown.shortfall.toStringAsFixed(2);

      _showMessage('Falta por cobrar: \$$falta', isError: true);

      return;
    }

    final hasNonCashOverage = breakdown.nonCashAmount > widget.total + 0.005;

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

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (messenger == null) {
      return;
    }

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
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
          constraints: const BoxConstraints(maxHeight: 600),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      const Text(
                        'Monto a cobrar',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
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
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildPaymentRow(row),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addPaymentRow,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Agregar tipo de pago'),
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
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Guardar cobro'),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(_PaymentRowData row) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _buildMethodDropdown(row)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Eliminar forma de pago',
                    onPressed: _rows.length > 1
                        ? () => _removePaymentRow(row.id)
                        : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey<String>('amount-${row.id}'),
                controller: row.controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (_) {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _buildMethodDropdown(row)),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey<String>('amount-${row.id}'),
                controller: row.controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
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
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMethodDropdown(_PaymentRowData row) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey<String>('method-${row.id}'),
          value: _methods.contains(row.method) ? row.method : _methods.first,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          items: _methods
              .map(
                (method) => DropdownMenuItem<String>(
                  value: method,
                  child: Text(
                    method,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            amount: _parseMoney(row.controller.text),
          ),
        )
        .toList();

    final breakdown = PaymentBreakdown(total: widget.total, payments: entries);

    final totalCollected = breakdown.totalCollected;
    final cashAmount = breakdown.cashAmount;
    final change = breakdown.change;
    final excess = breakdown.excess;
    final shortfall = breakdown.shortfall;

    return Container(
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
              .where((entry) => entry.method != 'Efectivo' && entry.amount > 0)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
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
              _buildWarningBox('\$${excess.toStringAsFixed(2)}'),
          ] else if (totalCollected < widget.total - 0.005)
            _buildErrorBox('\$${shortfall.toStringAsFixed(2)}')
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _summaryRow(String label, String value, {bool small = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: small ? 11 : 12, color: Colors.black54),
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

  Widget _buildSuccessBox(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(6),
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

// ============================================================
// MÉTRICAS
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
