import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/sale_model.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/printer_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({
    super.key,
    required this.sale,
  });

  final SaleModel sale;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final PrinterService _printerService = PrinterService();
  final SyncService _syncService = SyncService();
  final CatalogService _catalogService = CatalogService();
  final LocalDb _localDb = LocalDb();

  bool _printing = false;
  bool _syncing = false;

  // Estado de sincronización real almacenado en SQLite.
  String _currentSyncStatus = '';

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();

    _currentSyncStatus = widget.sale.syncStatus;

    _loadCurrentSaleStatus();
  }

  // ============================================================
  // RECARGAR ESTADO REAL DE LA VENTA
  // ============================================================

  Future<void> _loadCurrentSaleStatus() async {
    try {
      final currentSale =
          await _localDb.getSaleById(widget.sale.id);

      if (!mounted || currentSale == null) {
        return;
      }

      setState(() {
        _currentSyncStatus =
            currentSale['sync_status']?.toString() ??
                widget.sale.syncStatus;
      });
    } catch (_) {
      // Mantener el estado recibido originalmente.
    }
  }

  // ============================================================
  // ESTADO
  // ============================================================

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';

      case 'paid':
        return 'Pagada / sin sincronizar';

      case 'synced':
        return 'Sincronizada';

      case 'failed':
        return 'Fallida';

      default:
        return 'Borrador';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;

      case 'paid':
        return Colors.blue;

      case 'synced':
        return Colors.green;

      case 'failed':
        return Colors.red;

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // SINCRONIZAR VENTAS Y CATÁLOGO
  // ============================================================

  Future<void> _syncPendingSalesAndCatalog() async {
    if (_syncing || _printing) {
      return;
    }

    setState(() {
      _syncing = true;
    });

    try {
      final companyId =
          await AppStorage().getEmpresaId() ?? 0;

      final userId =
          await AppStorage().getUserId() ?? 0;

      final rawBusinessDate =
          await AppStorage().getBusinessDate();

      final businessDate =
          DateTime.tryParse(
                rawBusinessDate ?? '',
              ) ??
              DateTime.now();

      if (companyId <= 0) {
        throw Exception(
          'No se encontró la empresa de la sesión.',
        );
      }

      if (userId <= 0) {
        throw Exception(
          'No se encontró el usuario de la sesión.',
        );
      }

      // ----------------------------------------------------------
      // 1. SUBIR VENTAS PENDIENTES
      // ----------------------------------------------------------

      await _syncService.syncPendingSales(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // 2. RECARGAR ESTADO DE LA VENTA
      // ----------------------------------------------------------
      //
      // SyncService -> markSaleAsSynced()
      // cambia:
      //
      // sync_status = synced
      //
      // pero mantiene:
      //
      // status = paid
      //
      // Por eso debemos volver a leer SQLite.
      //

      await _loadCurrentSaleStatus();

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // 3. ACTUALIZAR CATÁLOGO
      // ----------------------------------------------------------

      final products =
          await _catalogService.syncCatalog(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
      );

      if (!mounted) {
        return;
      }

      // Volver a leer una vez más por seguridad.
      await _loadCurrentSaleStatus();

      if (!mounted) {
        return;
      }

      if (_currentSyncStatus == 'synced') {
        if (products.isEmpty) {
          _showMessage(
            'Venta sincronizada correctamente. '
            'El catálogo ya estaba actualizado.',
          );
        } else {
          _showMessage(
            'Venta sincronizada y catálogo actualizado: '
            '${products.length} productos.',
          );
        }
      } else {
        _showMessage(
          'Sincronización finalizada, pero esta venta todavía '
          'no aparece como sincronizada.',
          error: true,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      // Aunque exista un error, intentamos refrescar el estado
      // real de la venta desde SQLite.
      await _loadCurrentSaleStatus();

      if (!mounted) {
        return;
      }

      _showMessage(
        'No fue posible sincronizar: $error',
        error: true,
      );
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        _syncing = false;
      });
    }
  }

  // ============================================================
  // REIMPRIMIR TICKET
  // ============================================================

  Future<void> _reprintTicket() async {
    if (_printing || _syncing) {
      return;
    }

    if (widget.sale.items.isEmpty) {
      _showMessage(
        'La venta no contiene productos para imprimir.',
        error: true,
      );
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      var connected =
          await _printerService.bluetoothConnected();

      if (!connected) {
        connected =
            await _printerService.reconnectSelectedPrinter();
      }

      if (!connected) {
        throw Exception(
          'No hay una impresora Bluetooth conectada. '
          'Selecciona una impresora desde Configuración > Impresoras.',
        );
      }

      final saleItems =
          widget.sale.items.map((item) {
        return <String, dynamic>{
          'product_id': item.productId,
          'name': item.name,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total': item.total,
        };
      }).toList();

      final payments =
          widget.sale.payments.map((payment) {
        return <String, dynamic>{
          'method': payment.method,
          'amount': payment.amount,
        };
      }).toList();

      final totalPaid =
          widget.sale.payments.fold<double>(
        0,
        (sum, payment) =>
            sum + payment.amount,
      );

      final saleForPrint =
          <String, dynamic>{
        'id': widget.sale.id,
        'folio':
            widget.sale.folio ??
                widget.sale.uuidLocal,
        'fecha':
            widget.sale.createdAt.isNotEmpty
                ? widget.sale.createdAt
                : widget.sale.businessDate,
        'items': saleItems,
        'total': widget.sale.total,
        'payments': payments,
        'cashReceived': totalPaid,
        'changeDue':
            widget.sale.changeDue ?? 0,
      };

      final result =
          await _printerService.printSale(
        saleForPrint,
      );

      if (!mounted) {
        return;
      }

      if (!result.success) {
        _showMessage(
          result.message.isEmpty
              ? 'No fue posible reimprimir el ticket.'
              : result.message,
          error: true,
        );
        return;
      }

      _showMessage(
        'Ticket reimpreso correctamente.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'No fue posible reimprimir el ticket: $error',
        error: true,
      );
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        _printing = false;
      });
    }
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _showMessage(
    String message, {
    bool error = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              error ? Colors.red : null,
          behavior:
              SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE:
    //
    // El estado comercial de la venta puede seguir siendo "paid".
    // El estado que determina si ya fue sincronizada es
    // "sync_status".
    //
    // Por eso NO hacemos:
    //
    // status ?? syncStatus
    //
    // y tampoco damos prioridad a "paid".

    final displayedStatus =
        _currentSyncStatus.isNotEmpty
            ? _currentSyncStatus
            : widget.sale.syncStatus;

    final statusColor =
        _statusColor(displayedStatus);

    final title =
        widget.sale.folio ??
            (widget.sale.uuidLocal.length >= 8
                ? widget.sale.uuidLocal
                    .substring(0, 8)
                : widget.sale.uuidLocal);

    final busy =
        _printing || _syncing;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Venta $title',
        ),
        actions: [
          // ======================================================
          // SINCRONIZAR
          // ======================================================

          IconButton(
            tooltip:
                'Sincronizar ventas y catálogo',
            onPressed:
                busy
                    ? null
                    : _syncPendingSalesAndCatalog,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.sync_outlined,
                  ),
          ),

          // ======================================================
          // REIMPRIMIR
          // ======================================================

          IconButton(
            tooltip: 'Reimprimir ticket',
            onPressed:
                busy
                    ? null
                    : _reprintTicket,
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.print_outlined,
                  ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // ====================================================
            // ESTADO
            // ====================================================

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(16),

              decoration:
                  BoxDecoration(
                color: statusColor
                    .withAlpha(25),
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estado',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(
                    _statusLabel(
                      displayedStatus,
                    ),

                    style:
                        const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  Align(
                    alignment:
                        Alignment.centerRight,

                    child: Chip(
                      backgroundColor:
                          statusColor,

                      label: Text(
                        _statusLabel(
                          displayedStatus,
                        ),

                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ====================================================
            // INFORMACIÓN
            // ====================================================

            Text(
              'Fecha: ${widget.sale.businessDate}',

              style:
                  const TextStyle(
                fontSize: 14,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              'Total: \$${widget.sale.total.toStringAsFixed(2)}',

              style:
                  const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ====================================================
            // SINCRONIZACIÓN
            // ====================================================

            Card(
              elevation: 0,

              color:
                  Colors.blue.shade50,

              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),

                side: BorderSide(
                  color:
                      Colors.blue.shade100,
                ),
              ),

              child: Padding(
                padding:
                    const EdgeInsets.all(16),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,

                          decoration:
                              BoxDecoration(
                            color: Colors
                                .blue
                                .shade100,

                            borderRadius:
                                BorderRadius
                                    .circular(
                              12,
                            ),
                          ),

                          child: Icon(
                            _syncing
                                ? Icons.sync
                                : Icons
                                    .cloud_sync_outlined,

                            color:
                                Colors.blue
                                    .shade700,
                          ),
                        ),

                        const SizedBox(
                          width: 12,
                        ),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,

                            children: [
                              const Text(
                                'Sincronización',

                                style:
                                    TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                ),
                              ),

                              const SizedBox(
                                height: 3,
                              ),

                              Text(
                                _syncing
                                    ? 'Subiendo ventas pendientes y actualizando catálogo...'
                                    : displayedStatus ==
                                            'synced'
                                        ? 'Esta venta ya está sincronizada con el servidor.'
                                        : 'Sube ventas pendientes y después actualiza el catálogo.',

                                style:
                                    const TextStyle(
                                  fontSize: 13,
                                  color: Colors
                                      .black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    SizedBox(
                      width:
                          double.infinity,

                      child:
                          FilledButton
                              .icon(
                        onPressed:
                            busy
                                ? null
                                : _syncPendingSalesAndCatalog,

                        icon: _syncing
                            ? const SizedBox(
                                width:
                                    18,
                                height:
                                    18,

                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                  color:
                                      Colors.white,
                                ),
                              )
                            : Icon(
                                displayedStatus ==
                                        'synced'
                                    ? Icons
                                        .cloud_done_outlined
                                    : Icons
                                        .sync_outlined,
                              ),

                        label: Text(
                          _syncing
                              ? 'Sincronizando...'
                              : displayedStatus ==
                                      'synced'
                                  ? 'Sincronizar nuevamente'
                                  : 'Sincronizar ventas y catálogo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ====================================================
            // PAGOS
            // ====================================================

            if (widget.sale.payments.isNotEmpty) ...[
              const Text(
                'Pagos',

                style:
                    TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              ...widget.sale.payments.map(
                (payment) => Card(
                  child: ListTile(
                    leading:
                        const Icon(
                      Icons.payments_outlined,
                      color:
                          Color(0xFF9AC53B),
                    ),

                    title:
                        Text(
                      payment.method,
                    ),

                    trailing:
                        Text(
                      '\$${payment.amount.toStringAsFixed(2)}',
                    ),
                  ),
                ),
              ),

              if (widget.sale.changeDue !=
                      null &&
                  widget.sale.changeDue! >
                      0.005) ...[
                const SizedBox(
                  height: 4,
                ),

                Card(
                  color:
                      Colors.blue.shade50,

                  child: ListTile(
                    leading:
                        const Icon(
                      Icons.undo_outlined,
                      color:
                          Colors.blue,
                    ),

                    title:
                        const Text(
                      'Cambio devuelto',
                    ),

                    trailing:
                        Text(
                      '- \$${widget.sale.changeDue!.toStringAsFixed(2)}',

                      style:
                          const TextStyle(
                        color:
                            Colors.blue,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(
                height: 16,
              ),
            ],

            // ====================================================
            // PRODUCTOS
            // ====================================================

            const Text(
              'Productos',

              style:
                  TextStyle(
                fontSize: 16,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            if (widget.sale.items.isEmpty)
              const Card(
                child: Padding(
                  padding:
                      EdgeInsets.all(16),

                  child: Text(
                    'Esta venta no contiene productos.',

                    style:
                        TextStyle(
                      color:
                          Colors.black54,
                    ),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,

                physics:
                    const NeverScrollableScrollPhysics(),

                itemCount:
                    widget.sale.items.length,

                itemBuilder:
                    (context, index) {
                  final item =
                      widget.sale.items[
                          index];

                  return Card(
                    child: ListTile(
                      title:
                          Text(
                        item.name,
                      ),

                      subtitle:
                          Text(
                        '${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}',
                      ),

                      trailing:
                          Text(
                        '\$${item.total.toStringAsFixed(2)}',

                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(
              height: 20,
            ),

            // ====================================================
            // REIMPRIMIR
            // ====================================================

            SizedBox(
              width:
                  double.infinity,

              child:
                  FilledButton.icon(
                onPressed:
                    busy
                        ? null
                        : _reprintTicket,

                icon: _printing
                    ? const SizedBox(
                        width: 19,
                        height: 19,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.print_outlined,
                      ),

                label: Text(
                  _printing
                      ? 'Imprimiendo ticket...'
                      : 'Reimprimir ticket',
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            // ====================================================
            // ERROR DE SINCRONIZACIÓN
            // ====================================================

            if (widget.sale.errorMessage !=
                    null &&
                widget.sale.errorMessage!
                    .isNotEmpty)
              Container(
                width:
                    double.infinity,

                padding:
                    const EdgeInsets.all(
                  12,
                ),

                decoration:
                    BoxDecoration(
                  color: Colors.red
                      .withAlpha(25),

                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),

                child: Text(
                  'Error: ${widget.sale.errorMessage}',

                  style:
                      const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
