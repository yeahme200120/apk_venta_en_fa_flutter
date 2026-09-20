import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/models/sale_model.dart';
import '../../core/models/ticket_data.dart';
import '../../core/network/api_client.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/printer_service.dart';
import '../../core/services/sync_orchestrator.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/whatsapp_service.dart';
import '../../core/storage/app_storage.dart';
import '../widgets/sync_progress_dialog.dart';
import '../widgets/sync_result_dialog.dart';
import 'pdf_preview_screen.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.sale});

  final SaleModel sale;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final PrinterService _printerService = PrinterService();

  // ignore: unused_field
  final SyncService _syncService = SyncService();

  // ignore: unused_field
  final CatalogService _catalogService = CatalogService();

  final LocalDb _localDb = LocalDb();

  final ApiClient _apiClient = ApiClient();

  bool _printing = false;
  bool _syncing = false;

  // ignore: unused_field
  bool _loadingCashOperations = false;

  String _currentSyncStatus = '';

  String _currentFolio = '';

  // ============================================================
  // ESTADO DE CAJA (métodos intactos por si se reactivan)
  // ============================================================
  //
  // Estos tres campos son usados por _loadCashOperations() y por
  // los helpers de impresión de movimientos. Aunque no se llaman
  // hoy desde la UI, se mantienen para no romper la compilación
  // y permitir reactivar la funcionalidad sin reescribir código.

  // ignore: unused_field
  List<Map<String, dynamic>> _cashOperations = const [];

  // ignore: unused_field
  double _cashIncome = 0;

  // ignore: unused_field
  double _cashExpense = 0;

  // ignore: unused_field
  final Set<String> _printingCashOperations = <String>{};

  @override
  void initState() {
    super.initState();

    _currentSyncStatus = widget.sale.syncStatus;

    _currentFolio = _resolveInitialSaleNumber();

    _loadCurrentSaleStatus();
  }

  // ============================================================
  // NÚMERO / FOLIO REAL DE LA VENTA
  // ============================================================

  String _cleanString(dynamic value) {
    if (value == null) {
      return '';
    }

    final result = value.toString().trim();

    if (result.isEmpty || result.toLowerCase() == 'null') {
      return '';
    }

    return result;
  }

  String _resolveInitialSaleNumber() {
    final folio = _cleanString(widget.sale.folio);

    if (folio.isNotEmpty) {
      return folio;
    }

    if (widget.sale.id > 0) {
      return widget.sale.id.toString();
    }

    final uuid = _cleanString(widget.sale.uuidLocal);

    if (uuid.isNotEmpty) {
      return uuid;
    }

    return '-';
  }

  String _resolveSaleNumberFromMap(Map<String, dynamic> sale) {
    final candidates = [
      sale['folio'],
      sale['server_folio'],
      sale['serverFolio'],
      sale['numero_venta'],
      sale['numeroVenta'],
      sale['sale_number'],
      sale['saleNumber'],
    ];

    for (final candidate in candidates) {
      final value = _cleanString(candidate);

      if (value.isNotEmpty) {
        return value;
      }
    }

    final localId = int.tryParse('${sale['id'] ?? 0}') ?? 0;

    if (localId > 0) {
      return localId.toString();
    }

    final uuid = _cleanString(sale['uuid_local']);

    if (uuid.isNotEmpty) {
      return uuid;
    }

    return _resolveInitialSaleNumber();
  }

  String _saleNumber() {
    final current = _cleanString(_currentFolio);

    if (current.isNotEmpty) {
      return current;
    }

    return _resolveInitialSaleNumber();
  }

  // ============================================================
  // RECARGAR ESTADO REAL DE LA VENTA
  // ============================================================

  Future<void> _loadCurrentSaleStatus() async {
    try {
      final currentSale = await _localDb.getSaleById(widget.sale.id);

      if (!mounted || currentSale == null) {
        return;
      }

      final currentFolio = _resolveSaleNumberFromMap(currentSale);

      setState(() {
        _currentSyncStatus =
            currentSale['sync_status']?.toString() ?? widget.sale.syncStatus;

        _currentFolio = currentFolio;
      });
    } catch (_) {
      // Mantener el estado original.
    }
  }

  // ============================================================
  // OPERACIONES DE CAJA
  // (Métodos intactos por si se reactivan más adelante)
  // ============================================================

  // ignore: unused_element
  Future<void> _loadCashOperations() async {
    if (_loadingCashOperations) {
      return;
    }

    setState(() {
      _loadingCashOperations = true;
    });

    try {
      final operations = await _apiClient.getCashOperations();

      var income = 0.0;
      var expense = 0.0;

      for (final operation in operations) {
        final amount = _toDouble(
          operation['importe'] ?? operation['monto'] ?? operation['amount'],
        );

        if (_isIncomeMovement(operation)) {
          income += amount.abs();
        } else {
          expense += amount.abs();
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _cashOperations = List<Map<String, dynamic>>.from(operations);

        _cashIncome = income;
        _cashExpense = expense;
      });
    } catch (error) {
      debugPrint('[CAJA] Error cargando movimientos: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _cashOperations = const [];
        _cashIncome = 0;
        _cashExpense = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCashOperations = false;
        });
      }
    }
  }

  // ============================================================
  // CLASIFICACIÓN DE MOVIMIENTOS
  // ============================================================

  // ignore: unused_element
  bool _isCashIncome(String type) {
    return type == 'ingreso' ||
        type == 'income' ||
        type == 'entrada' ||
        type == 'deposito' ||
        type == 'depósito' ||
        type == 'venta' ||
        type == 'apertura' ||
        type == 'cash_in' ||
        type == 'cash-in' ||
        type == 'cashin';
  }

  // ignore: unused_element
  bool _isCashExpense(String type) {
    return type == 'egreso' ||
        type == 'expense' ||
        type == 'salida' ||
        type == 'retiro' ||
        type == 'devolucion' ||
        type == 'devolución' ||
        type == 'withdrawal' ||
        type == 'refund' ||
        type == 'cash_out' ||
        type == 'cash-out' ||
        type == 'cashout';
  }

  // ignore: unused_element
  bool _isIncomeMovement(Map<String, dynamic> operation) {
    final type = _operationType(operation);

    if (_isCashIncome(type)) {
      return true;
    }

    if (_isCashExpense(type)) {
      return false;
    }

    final amount = _toDouble(
      operation['importe'] ?? operation['monto'] ?? operation['amount'],
    );

    return amount >= 0;
  }

  // ignore: unused_element
  bool _isPrintableMovement(Map<String, dynamic> operation) {
    if (operation.isEmpty) {
      return false;
    }

    final type = _operationType(operation);

    return type.isNotEmpty ||
        operation['id'] != null ||
        operation['movimiento_id'] != null ||
        operation['importe'] != null ||
        operation['monto'] != null ||
        operation['amount'] != null;
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value == null) {
      return 0;
    }

    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _operationType(Map<String, dynamic> operation) {
    return (operation['tipo'] ??
            operation['type'] ??
            operation['movimiento_tipo'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
  }

  // ignore: unused_element
  String _operationTypeLabel(String type) {
    switch (type) {
      case 'ingreso':
      case 'income':
      case 'entrada':
      case 'cash_in':
      case 'cash-in':
      case 'cashin':
        return 'Ingreso';

      case 'egreso':
      case 'expense':
      case 'salida':
      case 'cash_out':
      case 'cash-out':
      case 'cashout':
        return 'Egreso';

      case 'retiro':
      case 'withdrawal':
        return 'Retiro';

      case 'devolucion':
      case 'devolución':
      case 'refund':
        return 'Devolución';

      case 'apertura':
        return 'Apertura';

      case 'venta':
        return 'Venta';

      case 'deposito':
      case 'depósito':
        return 'Depósito';

      case 'ajuste':
      case 'adjustment':
        return 'Ajuste';

      default:
        return type.isEmpty ? 'Movimiento' : type;
    }
  }

  // ignore: unused_element
  String _operationConcept(Map<String, dynamic> operation) {
    final concept =
        operation['concepto'] ??
        operation['descripcion'] ??
        operation['description'] ??
        operation['motivo'] ??
        operation['observaciones'] ??
        operation['notas'];

    if (concept != null && concept.toString().trim().isNotEmpty) {
      return concept.toString().trim();
    }

    return _operationTypeLabel(_operationType(operation));
  }

  // ignore: unused_element
  String _operationDate(Map<String, dynamic> operation) {
    final value =
        operation['created_at'] ??
        operation['createdAt'] ??
        operation['fecha'] ??
        operation['fecha_hora'] ??
        operation['fechaHora'] ??
        operation['date'];

    if (value == null || value.toString().trim().isEmpty) {
      return '-';
    }

    final parsed = DateTime.tryParse(value.toString());

    if (parsed == null) {
      return value.toString();
    }

    final local = parsed.toLocal();

    final day = local.day.toString().padLeft(2, '0');

    final month = local.month.toString().padLeft(2, '0');

    final year = local.year.toString();

    final hour = local.hour.toString().padLeft(2, '0');

    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year '
        '$hour:$minute';
  }

  // ignore: unused_element
  String _cashOperationKey(Map<String, dynamic> operation, int index) {
    final id =
        operation['id'] ??
        operation['movimiento_id'] ??
        operation['movimientoId'] ??
        operation['uuid'] ??
        operation['uuid_local'] ??
        operation['uuidLocal'];

    if (id != null && id.toString().trim().isNotEmpty) {
      return id.toString().trim();
    }

    return '${_operationType(operation)}_$index';
  }

  // ============================================================
  // IMPRIMIR MOVIMIENTO DE CAJA
  // (Método intacto por si se reactiva)
  // ============================================================

  // ignore: unused_element
  Future<void> _printCashOperation({
    required Map<String, dynamic> operation,
    required int index,
  }) async {
    if (_printing || _syncing) {
      return;
    }

    if (!_isPrintableMovement(operation)) {
      _showMessage(
        'El movimiento no contiene información suficiente para imprimir.',
        error: true,
      );
      return;
    }

    final operationKey = _cashOperationKey(operation, index);

    if (_printingCashOperations.contains(operationKey)) {
      return;
    }

    setState(() {
      _printing = true;

      _printingCashOperations.add(operationKey);
    });

    try {
      final connected = await _printerService.ensureBluetoothConnection();

      if (!connected) {
        throw Exception(
          'No hay una impresora Bluetooth seleccionada o no fue posible conectarla.',
        );
      }

      final income = _isIncomeMovement(operation);

      final PrintOperationResult result;

      if (income) {
        result = await _printerService.printIncome(operation);
      } else {
        result = await _printerService.printExpense(operation);
      }

      if (!mounted) {
        return;
      }

      if (!result.success) {
        _showMessage(
          result.message.isEmpty
              ? 'No fue posible imprimir el movimiento.'
              : result.message,
          error: true,
        );
        return;
      }

      _showMessage(
        income
            ? 'Ingreso impreso correctamente.'
            : 'Egreso impreso correctamente.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'No fue posible imprimir el movimiento: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _printingCashOperations.remove(operationKey);

          _printing = false;
        });
      }
    }
  }

  // ============================================================
  // DETALLE DE MOVIMIENTO
  // (Método intacto por si se reactiva)
  // ============================================================

  // ignore: unused_element
  Future<void> _showCashMovementDetail({
    required Map<String, dynamic> operation,
    required int index,
  }) async {
    final type = _operationType(operation);

    final income = _isIncomeMovement(operation);

    final amount = _toDouble(
      operation['importe'] ?? operation['monto'] ?? operation['amount'],
    );

    final id =
        operation['id'] ??
        operation['movimiento_id'] ??
        operation['movimientoId'] ??
        operation['uuid'] ??
        operation['uuid_local'] ??
        operation['uuidLocal'];

    final reference = operation['referencia'] ?? operation['reference'];

    final user =
        operation['usuario'] ??
        operation['vendedor'] ??
        operation['userName'] ??
        operation['usuario_nombre'] ??
        operation['usuarioNombre'];

    final cashRegister =
        operation['caja_id'] ??
        operation['cajaId'] ??
        operation['turno_caja_id'] ??
        operation['turnoCajaId'] ??
        operation['cash_register_id'];

    final concept = _operationConcept(operation);

    final date = _operationDate(operation);

    final title = _operationTypeLabel(type);

    final operationKey = _cashOperationKey(operation, index);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final tone = income ? cs.primary : cs.error;

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        income
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: tone,
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalle del movimiento',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tone.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Importe',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${income ? '+' : '-'}\$${amount.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: tone,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _movementDetailRow('Tipo', title),

                _movementDetailRow('Concepto', concept),

                _movementDetailRow('Fecha', date),

                if (id != null) _movementDetailRow('ID', id.toString()),

                if (reference != null && reference.toString().trim().isNotEmpty)
                  _movementDetailRow('Referencia', reference.toString().trim()),

                if (user != null && user.toString().trim().isNotEmpty)
                  _movementDetailRow('Usuario', user.toString().trim()),

                if (cashRegister != null)
                  _movementDetailRow('Turno / caja', cashRegister.toString()),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _printing ||
                            _syncing ||
                            _printingCashOperations.contains(operationKey)
                        ? null
                        : () async {
                            Navigator.of(context).pop();

                            await _printCashOperation(
                              operation: operation,
                              index: index,
                            );
                          },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir movimiento'),
                  ),
                ),

                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _movementDetailRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SINCRONIZAR VENTAS Y CATÁLOGO
  //
  // Ya no se invoca desde la UI (la sincronización corre
  // automáticamente desde AutomaticSyncService y desde el
  // botón global del HomeShell). Se conserva por si se
  // requiere reactivar como acción manual.
  // ============================================================

  // ignore: unused_element
  Future<void> _syncPendingSalesAndCatalog() async {
    if (_syncing || _printing) {
      return;
    }

    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    final rawBusinessDate = await AppStorage().getServerBusinessDate();
    final businessDate =
        DateTime.tryParse(rawBusinessDate ?? '') ?? DateTime.now();

    if (companyId <= 0 || userId <= 0) {
      _showMessage(
        'No existe una sesión válida para sincronizar.',
        error: true,
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _syncing = true;
    });

    final progressNotifier = ValueNotifier<String>(
      'Iniciando sincronización...',
    );

    NavigatorState? progressNavigator;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          progressNavigator = Navigator.of(ctx, rootNavigator: true);

          return SyncProgressDialog(
            progressNotifier: progressNotifier,
            title: 'Sincronizando venta',
          );
        },
      ),
    );

    await Future.delayed(const Duration(milliseconds: 120));

    try {
      final report = await SyncOrchestrator().syncAll(
        companyId: companyId,
        userId: userId,
        businessDate: businessDate,
        onProgress: (stage, message) {
          progressNotifier.value = message;
        },
      );

      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!mounted) return;

      await _loadCurrentSaleStatus();

      if (!mounted) return;

      await showSyncResultDialog(
        context,
        report: report,
        onRetry: () => _syncPendingSalesAndCatalog(),
      );
    } catch (error) {
      if (progressNavigator != null && progressNavigator!.canPop()) {
        progressNavigator!.pop();
      }

      progressNotifier.dispose();

      if (!mounted) return;

      await _loadCurrentSaleStatus();

      if (!mounted) return;

      _showMessage(
        'No fue posible sincronizar: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  // ============================================================
  // VISTA PREVIA PDF
  // ============================================================

  void _openPdfPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PdfPreviewScreen(sale: widget.sale)),
    );
  }

  // ============================================================
  // COMPARTIR TICKET POR WHATSAPP
  // ============================================================

  Future<void> _shareTicketToWhatsApp() async {
    if (_printing || _syncing) {
      return;
    }

    if (widget.sale.items.isEmpty) {
      _showMessage(
        'La venta no contiene productos para compartir.',
        error: true,
      );
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      final config = await _printerService.loadTicketConfig();

      final ticket = TicketData.fromSale(sale: widget.sale, config: config);

      final Uint8List pdfBytes = await PdfService.generateSalePdf(
        ticket: ticket,
      );

      final folio = _saleNumber();

      final fileName = folio.isNotEmpty
          ? 'ticket_$folio.pdf'
          : 'ticket_${widget.sale.uuidLocal}.pdf';

      final shared = await WhatsAppService.sharePdf(
        bytes: pdfBytes,
        fileName: fileName,
        text: 'Ticket de venta $folio',
      );

      if (!mounted) {
        return;
      }

      if (!shared) {
        _showMessage(
          'No fue posible abrir el selector para compartir el ticket.',
          error: true,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('No fue posible compartir el ticket: $error', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  // ============================================================
  // REIMPRIMIR TICKET DE VENTA
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
      final connected = await _printerService.ensureBluetoothConnection();

      if (!connected) {
        throw Exception(
          'No hay una impresora Bluetooth seleccionada o no fue posible conectarla.',
        );
      }

      final saleItems = widget.sale.items.map((item) {
        return <String, dynamic>{
          'product_id': item.productId,
          'name': item.name,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'total': item.total,
        };
      }).toList();

      final payments = widget.sale.payments.map((payment) {
        return <String, dynamic>{
          'method': payment.method,
          'amount': payment.amount,
        };
      }).toList();

      final totalPaid = widget.sale.payments.fold<double>(
        0,
        (sum, payment) => sum + payment.amount,
      );

      final saleForPrint = <String, dynamic>{
        'id': widget.sale.id,
        'folio': _saleNumber(),
        'fecha': widget.sale.createdAt.isNotEmpty
            ? widget.sale.createdAt
            : widget.sale.businessDate,
        'items': saleItems,
        'total': widget.sale.total,
        'payments': payments,
        'cashReceived': totalPaid,
        'changeDue': widget.sale.changeDue ?? 0,
      };

      final result = await _printerService.printSale(saleForPrint);

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

      _showMessage('Ticket reimpreso correctamente.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('No fue posible reimprimir el ticket: $error', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    final cs = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? cs.error : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // ESTADOS
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
    final cs = Theme.of(context).colorScheme;

    switch (status) {
      case 'pending':
        return cs.tertiary;

      case 'paid':
        return cs.secondary;

      case 'synced':
        return cs.primary;

      case 'failed':
        return cs.error;

      default:
        return cs.onSurfaceVariant;
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final displayedStatus = _currentSyncStatus.isNotEmpty
        ? _currentSyncStatus
        : widget.sale.syncStatus;

    final statusColor = _statusColor(displayedStatus);

    final title = _saleNumber();

    final busy = _printing || _syncing;

    final isSynced = displayedStatus == 'synced';

    return Scaffold(
      appBar: AppBar(
        title: Text('Venta $title'),

        actions: [
          IconButton(
            tooltip: 'Ver PDF',
            onPressed: busy ? null : _openPdfPreview,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),

          IconButton(
            tooltip: 'Compartir por WhatsApp',
            onPressed: busy ? null : _shareTicketToWhatsApp,
            icon: const Icon(Icons.chat_outlined),
          ),

          IconButton(
            tooltip: 'Reimprimir ticket',
            onPressed: busy ? null : _reprintTicket,
            icon: _printing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: () async {
          await _loadCurrentSaleStatus();
        },

        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // ==================================================
              // ESTADO
              // ==================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        isSynced
                            ? Icons.cloud_done_outlined
                            : Icons.receipt_long_outlined,
                        color: statusColor,
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estado de la venta',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _statusLabel(displayedStatus),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Chip(
                      backgroundColor: statusColor,
                      label: Text(
                        _statusLabel(displayedStatus),
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ==================================================
              // INFORMACIÓN GENERAL
              // ==================================================
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _infoRow('Folio', title),

                      const Divider(height: 18),

                      _infoRow('Fecha comercial', widget.sale.businessDate),

                      const Divider(height: 18),

                      _infoRow(
                        'Registro',
                        widget.sale.createdAt.isNotEmpty
                            ? widget.sale.createdAt
                            : '-',
                      ),

                      const Divider(height: 18),

                      _infoRow(
                        'Total',
                        '\$${widget.sale.total.toStringAsFixed(2)}',
                        valueBold: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ==================================================
              // PAGOS DE ESTA VENTA
              // ==================================================
              const Text(
                'Pagos de esta venta',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              if (widget.sale.payments.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Esta venta no tiene pagos registrados.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              else ...[
                ...widget.sale.payments.map(
                  (payment) => Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.payments_outlined,
                        color: cs.primary,
                      ),
                      title: Text(payment.method),
                      trailing: Text(
                        '\$${payment.amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),

                if (widget.sale.changeDue != null &&
                    widget.sale.changeDue! > 0.005)
                  Card(
                    color: cs.secondaryContainer.withValues(alpha: 0.5),
                    child: ListTile(
                      leading: Icon(
                        Icons.undo_outlined,
                        color: cs.secondary,
                      ),
                      title: const Text('Cambio devuelto'),
                      trailing: Text(
                        '- \$${widget.sale.changeDue!.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: cs.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 24),

              // ==================================================
              // PRODUCTOS
              // ==================================================
              const Text(
                'Productos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              if (widget.sale.items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Esta venta no contiene productos.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.sale.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.sale.items[index];

                    return Card(
                      child: ListTile(
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.quantity} x \$${item.unitPrice.toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          '\$${item.total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 24),

              // ==================================================
              // REIMPRIMIR VENTA
              // ==================================================
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _reprintTicket,
                  icon: _printing
                      ? SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(
                    _printing ? 'Imprimiendo...' : 'Reimprimir ticket',
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ==================================================
              // ERROR DE SINCRONIZACIÓN
              // ==================================================
              if (widget.sale.errorMessage != null &&
                  widget.sale.errorMessage!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Error de sincronización: '
                    '${widget.sale.errorMessage}',
                    style: TextStyle(color: cs.error),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // INFORMACIÓN
  // ============================================================

  Widget _infoRow(String label, String value, {bool valueBold = false}) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),

        const SizedBox(width: 16),

        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: valueBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RESUMEN DE CAJA
  // (Método intacto por si se reactiva)
  // ============================================================

  // ignore: unused_element
  Widget _cashSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),

            const SizedBox(height: 12),

            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              '\$${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}