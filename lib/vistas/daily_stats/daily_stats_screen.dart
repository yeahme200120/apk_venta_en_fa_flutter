import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/local_db.dart';
import '../../core/database/pos_db_service.dart';
import '../../core/models/sale_model.dart';
import '../../core/network/api_client.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../ventas/sale_detail_screen.dart';

// ============================================================
// MODELO DE EGRESO
// ============================================================

class _Egreso {
  const _Egreso({
    required this.id,
    required this.uuid,
    required this.concepto,
    required this.monto,
    this.formaPago,
    required this.registradoAt,
  });

  final int id;
  final String uuid;
  final String concepto;
  final double monto;
  final String? formaPago;
  final DateTime registradoAt;
}

// ============================================================
// MODELO DE INGRESO MANUAL
// ============================================================

class _Ingreso {
  const _Ingreso({
    required this.id,
    required this.uuid,
    required this.concepto,
    required this.monto,
    this.formaPago,
    required this.registradoAt,
  });

  final int id;
  final String uuid;
  final String concepto;
  final double monto;
  final String? formaPago;
  final DateTime registradoAt;
}

// ============================================================
// PANTALLA PRINCIPAL
// ============================================================

class DailyStatsScreen extends StatefulWidget {
  const DailyStatsScreen({super.key});

  @override
  State<DailyStatsScreen> createState() => _DailyStatsScreenState();
}

class _DailyStatsScreenState extends State<DailyStatsScreen>
    with WidgetsBindingObserver {
  final LocalDb _historyDb = LocalDb();
  final PosDatabaseService _dayDb = PosDatabaseService();
  final SyncService _syncService = SyncService();
  final ApiClient _apiClient = ApiClient();

  StreamSubscription<void>? _salesChangesSubscription;
  bool _refreshQueued = false;

  bool _loading = true;
  bool _refreshing = false;
  bool _syncing = false;

  List<Map<String, dynamic>> _sales = const [];
  List<_Egreso> _egresos = const [];
  List<_Ingreso> _ingresos = const []; // ingresos manuales (no ventas)

  // Nombre del negocio
  String _companyName = '';

  // Filtro de rango de fechas (por defecto hoy)
  DateTime _fechaInicio = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _fechaFin = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  );

  // Búsqueda en la lista
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _salesChangesSubscription = LocalDb.salesChanges.listen((_) {
      if (!mounted || _syncing) return;
      if (_refreshing) { _refreshQueued = true; return; }
      _refreshSilently();
    });

    _initialize();
  }

  Future<void> _initialize() async {
    final name = await AppStorage().getCompanyName();
    if (mounted) setState(() => _companyName = name ?? '');
    await _loadStats();
    if (!mounted) return;
    try {
      final offline = await AppStorage().isOfflineSession();
      if (!offline) {
        await _syncService.syncPull();
        if (mounted) await _loadStats();
      }
    } catch (e) {
      debugPrint('ℹ️ Pull inicial no disponible: $e');
    }
  }

  @override
  void dispose() {
    _salesChangesSubscription?.cancel();
    _salesChangesSubscription = null;
    _searchCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_syncing) {
      _syncAndRefreshOnResume();
    }
  }

  Future<void> _syncAndRefreshOnResume() async {
    try {
      final offline = await AppStorage().isOfflineSession();
      if (!offline) await _syncService.syncPull();
    } catch (_) {}
    if (mounted) await _refreshSilently();
  }

  // ============================================================
  // CARGA
  // ============================================================

  Future<void> _loadStats() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    try {
      final sales = await _loadSalesInRange();
      final egresos = await _loadEgresos();
      final ingresos = await _loadIngresos();
      if (!mounted) return;
      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _egresos = egresos;
        _ingresos = ingresos;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('No fue posible cargar las ventas: $error', isError: true);
    } finally {
      _refreshing = false;
      _scheduleQueuedRefresh();
    }
  }

  Future<void> _refreshSilently() async {
    if (!mounted || _refreshing || _syncing) return;
    _refreshing = true;
    try {
      final sales = await _loadSalesInRange();
      final egresos = await _loadEgresos();
      final ingresos = await _loadIngresos();
      if (!mounted) return;
      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _egresos = egresos;
        _ingresos = ingresos;
      });
    } catch (_) {
    } finally {
      _refreshing = false;
      _scheduleQueuedRefresh();
    }
  }

  void _scheduleQueuedRefresh() {
    if (!_refreshQueued || !mounted || _syncing || _refreshing) return;
    _refreshQueued = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_syncing && !_refreshing) _refreshSilently();
    });
  }

  // ============================================================
  // VENTAS EN RANGO
  // ============================================================

  Future<List<Map<String, dynamic>>> _loadSalesInRange() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    // Construir clave de fecha para filtrar en la BD del historial
    final inicioClave = _dayDb.dateKey(_fechaInicio);
    final finClave = _dayDb.dateKey(_fechaFin);
    final esHoy = inicioClave == _dayDb.dateKey(DateTime.now());

    // Ventas del historial local: usar getSales si tenemos rango
    List<Map<String, dynamic>> historySales;
    try {
      if (esHoy) {
        // Para el día actual getTodaySales es más preciso (filtra por hora)
        historySales = await _historyDb.getTodaySales();
      } else {
        // Para fechas pasadas usamos filtro por business_date
        historySales = await _historyDb.getSales(
          businessDate: inicioClave,
        );
        // Si el rango abarca varios días, cargar cada uno
        if (inicioClave != finClave) {
          // Carga genérica sin filtro de fecha y filtramos abajo
          historySales = await _historyDb.getSales();
        }
      }
    } catch (_) {
      historySales = [];
    }

    // Ventas de la BD del día (solo para el día actual)
    List<Map<String, dynamic>> daySales = [];
    if (companyId > 0 && userId > 0 && esHoy) {
      try {
        daySales = await _dayDb.getTodaySales(
          companyId: companyId,
          userId: userId,
          businessDate: DateTime.now(),
        );
      } catch (_) {
        // BD del día no disponible (sesión offline o sin archivo)
      }
    }

    final unique = <String, Map<String, dynamic>>{};

    for (final raw in daySales) {
      final sale = Map<String, dynamic>.from(raw);
      final uuid = sale['uuid_local']?.toString().trim() ?? '';
      sale['_source'] = 'day';
      unique[uuid.isEmpty ? 'day-${sale['id']}' : uuid] = sale;
    }
    for (final raw in historySales) {
      final sale = Map<String, dynamic>.from(raw);
      final uuid = sale['uuid_local']?.toString().trim() ?? '';
      sale['_source'] = 'history';
      if (uuid.isEmpty) { unique['history-${sale['id']}'] = sale; continue; }
      if (!unique.containsKey(uuid)) { unique[uuid] = sale; continue; }
      final current = unique[uuid]!;
      final cUpdated = _dateValue(current['updated_at']);
      final hUpdated = _dateValue(sale['updated_at']);
      if (hUpdated != null && (cUpdated == null || hUpdated.isAfter(cUpdated))) {
        unique[uuid] = sale; continue;
      }
      if ((hUpdated == null && cUpdated == null) ||
          (hUpdated != null && cUpdated != null &&
              hUpdated.isAtSameMomentAs(cUpdated))) {
        if ((sale['sync_status']?.toString().toLowerCase() ?? '') == 'synced' &&
            (current['sync_status']?.toString().toLowerCase() ?? '') != 'synced') {
          unique[uuid] = sale;
        }
      }
    }

    // Filtrar por rango de fechas usando created_at, paid_at o business_date
    final result = unique.values.where((s) {
      // Intentar con created_at
      DateTime? dt = _dateValue(s['created_at']);
      // Fallback: paid_at
      dt ??= _dateValue(s['paid_at']);
      // Fallback: business_date (solo fecha, sin hora)
      if (dt == null) {
        final bd = s['business_date']?.toString().trim() ?? '';
        if (bd.isNotEmpty) dt = DateTime.tryParse(bd);
      }
      if (dt == null) return true; // Sin fecha: incluir siempre
      return !dt.isBefore(_fechaInicio) && !dt.isAfter(_fechaFin);
    }).toList();

    result.sort((a, b) {
      final dateA = _dateValue(a['created_at']) ??
          _dateValue(a['paid_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = _dateValue(b['created_at']) ??
          _dateValue(b['paid_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });
    return result;
  }

  // ============================================================
  // EGRESOS
  // ============================================================

  Future<List<_Egreso>> _loadEgresos() async {
    try {
      final db = await _historyDb.database;
      await db.execute('''CREATE TABLE IF NOT EXISTS daily_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        concepto TEXT NOT NULL,
        monto REAL NOT NULL,
        forma_pago TEXT,
        registrado_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');

      final inicio = _fechaInicio.toIso8601String();
      final fin = _fechaFin.toIso8601String();

      final rows = await db.query(
        'daily_expenses',
        where: 'registrado_at >= ? AND registrado_at <= ?',
        whereArgs: [inicio, fin],
        orderBy: 'registrado_at DESC',
      );

      return rows.map((r) {
        final ts = DateTime.tryParse(r['registrado_at']?.toString() ?? '') ?? DateTime.now();
        return _Egreso(
          id: (r['id'] as num).toInt(),
          uuid: r['uuid']?.toString() ?? '',
          concepto: r['concepto']?.toString() ?? '',
          monto: (r['monto'] is num) ? (r['monto'] as num).toDouble() : 0.0,
          formaPago: r['forma_pago']?.toString(),
          registradoAt: ts.toLocal(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardarEgreso({required String concepto, required double monto, String? formaPago}) async {
    final db = await _historyDb.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('daily_expenses', {
      'uuid': 'egreso_${DateTime.now().millisecondsSinceEpoch}',
      'concepto': concepto,
      'monto': monto,
      'forma_pago': formaPago,
      'registrado_at': now,
      'sync_status': 'pending',
    });
    await _refreshSilently();
  }

  Future<void> _eliminarEgreso(int id) async {
    final db = await _historyDb.database;
    await db.delete('daily_expenses', where: 'id = ?', whereArgs: [id]);
    await _refreshSilently();
  }

  Future<void> _agregarEgreso() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MovimientoDialog(
        tipo: _TipoMovimiento.egreso,
        onGuardar: (concepto, monto, formaPago) async {
          Navigator.of(ctx).pop();
          await _guardarEgreso(concepto: concepto, monto: monto, formaPago: formaPago);
        },
      ),
    );
  }

  // ============================================================
  // INGRESOS MANUALES — CRUD LOCAL
  // ============================================================

  Future<List<_Ingreso>> _loadIngresos() async {
    try {
      final db = await _historyDb.database;
      await db.execute('''CREATE TABLE IF NOT EXISTS daily_incomes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        concepto TEXT NOT NULL,
        monto REAL NOT NULL,
        forma_pago TEXT,
        registrado_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');

      final inicio = _fechaInicio.toIso8601String();
      final fin = _fechaFin.toIso8601String();

      final rows = await db.query(
        'daily_incomes',
        where: 'registrado_at >= ? AND registrado_at <= ?',
        whereArgs: [inicio, fin],
        orderBy: 'registrado_at DESC',
      );

      return rows.map((r) {
        final ts = DateTime.tryParse(r['registrado_at']?.toString() ?? '') ?? DateTime.now();
        return _Ingreso(
          id: (r['id'] as num).toInt(),
          uuid: r['uuid']?.toString() ?? '',
          concepto: r['concepto']?.toString() ?? '',
          monto: (r['monto'] is num) ? (r['monto'] as num).toDouble() : 0.0,
          formaPago: r['forma_pago']?.toString(),
          registradoAt: ts.toLocal(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardarIngreso({
    required String concepto,
    required double monto,
    String? formaPago,
  }) async {
    final db = await _historyDb.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('daily_incomes', {
      'uuid': 'ingreso_${DateTime.now().millisecondsSinceEpoch}',
      'concepto': concepto,
      'monto': monto,
      'forma_pago': formaPago,
      'registrado_at': now,
      'sync_status': 'pending',
    });
    await _refreshSilently();
  }

  Future<void> _eliminarIngreso(int id) async {
    final db = await _historyDb.database;
    await db.delete('daily_incomes', where: 'id = ?', whereArgs: [id]);
    await _refreshSilently();
  }

  Future<void> _agregarIngreso() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MovimientoDialog(
        tipo: _TipoMovimiento.ingreso,
        onGuardar: (concepto, monto, formaPago) async {
          Navigator.of(ctx).pop();
          await _guardarIngreso(concepto: concepto, monto: monto, formaPago: formaPago);
        },
      ),
    );
  }

  // ============================================================
  // SELECTOR DE RANGO
  // ============================================================

  Future<void> _seleccionarFecha({required bool esInicio}) async {
    final inicial = esInicio ? _fechaInicio : _fechaFin;
    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = DateTime(picked.year, picked.month, picked.day);
        if (_fechaInicio.isAfter(_fechaFin)) {
          _fechaFin = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _fechaFin = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_fechaFin.isBefore(_fechaInicio)) {
          _fechaInicio = DateTime(picked.year, picked.month, picked.day);
        }
      }
    });
    await _loadStats();
  }

  // ============================================================
  // SINCRONIZACIÓN
  // ============================================================

  Future<void> _syncNow() async {
    if (!mounted || _syncing) return;
    setState(() => _syncing = true);
    try {
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;
      await _syncService.syncPendingSales(
          companyId: companyId, userId: userId, businessDate: DateTime.now());
      await _syncService.syncPull();
      if (mounted) await _loadStats();
      if (mounted) _showMessage('Sincronización completada.');
    } catch (error) {
      if (mounted) _showMessage('No fue posible sincronizar: $error', isError: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refreshSilently();
    }
  }

  // ============================================================
  // CANCELAR VENTA
  // ============================================================

  Future<void> _openSale(Map<String, dynamic> sale) async {
    if (!mounted) return;
    final saleId = _toInt(sale['id']);
    if (saleId <= 0) { _showMessage('No se pudo identificar la venta.', isError: true); return; }
    try {
      final source = sale['_source']?.toString() ?? 'history';
      List<Map<String, dynamic>> items = [];
      List<Map<String, dynamic>> payments = [];
      if (source == 'history') {
        items = await _historyDb.getSaleItemsBySaleId(saleId);
        payments = await _historyDb.getSalePaymentsBySaleId(saleId);
      } else {
        final companyId = await AppStorage().getEmpresaId() ?? 0;
        final userId = await AppStorage().getUserId() ?? 0;
        if (companyId <= 0 || userId <= 0) throw Exception('No existe una sesión válida.');
        final db = await _dayDb.open(companyId: companyId, userId: userId, businessDate: DateTime.now());
        items = await _dayDb.getSaleItems(db, saleId);
        payments = await _dayDb.getSalePayments(db, saleId);
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SaleDetailScreen(
          sale: SaleModel.fromMap(Map<String, dynamic>.from(sale),
              saleItems: items.map(SaleItemModel.fromMap).toList(),
              salePayments: payments.map(SalePaymentModel.fromMap).toList()),
        ),
      ));
      if (mounted) await _refreshSilently();
    } catch (error) {
      if (mounted) _showMessage('No fue posible abrir la venta: $error', isError: true);
    }
  }

  Future<void> _cancelSale(Map<String, dynamic> sale) async {
    if (!mounted) return;
    if (_businessStatus(sale) == _SaleBusinessStatus.cancelled) return;
    final saleId = _toInt(sale['id']);
    if (saleId <= 0) { _showMessage('No se pudo identificar la venta.', isError: true); return; }
    final confirmed = await _showCancelDialog();
    if (confirmed != true || !mounted) return;
    try {
      final source = sale['_source']?.toString() ?? 'history';
      if (source == 'history') {
        final serverId = _toInt(sale['server_id']);
        if (serverId > 0) {
          try { await _apiClient.cancelSale(serverId, reason: 'Cancelación desde POS'); }
          catch (error) { throw Exception('El servidor no confirmó la cancelación: $error'); }
        }
        final cancelled = await _historyDb.cancelSale(saleId);
        if (!cancelled) { _showMessage('La venta ya estaba cancelada o no existe.', isError: true); return; }
        if (serverId > 0) await _historyDb.updateSaleStatus(saleId, 'cancelled', syncStatus: 'synced');
        await _refreshSilently();
        if (mounted) _showMessage(serverId > 0 ? 'Venta cancelada correctamente.' : 'Venta cancelada localmente.');
        return;
      }
      final companyId = await AppStorage().getEmpresaId() ?? 0;
      final userId = await AppStorage().getUserId() ?? 0;
      if (companyId <= 0 || userId <= 0) throw Exception('No existe una sesión válida para cancelar la venta.');
      final db = await _dayDb.open(companyId: companyId, userId: userId, businessDate: DateTime.now());
      final serverId = _toInt(sale['server_id']);
      if (serverId > 0) {
        try { await _apiClient.cancelSale(serverId, reason: 'Cancelación desde POS'); }
        catch (error) { throw Exception('El servidor no confirmó la cancelación: $error'); }
      }
      final cancelled = await _cancelDaySale(db, saleId);
      if (!cancelled) { await _refreshSilently(); _showMessage('La venta ya estaba cancelada o no existe.', isError: true); return; }
      await _refreshSilently();
      if (mounted) _showMessage(serverId > 0 ? 'Venta cancelada correctamente.' : 'Venta cancelada localmente.');
    } catch (error) {
      if (mounted) _showMessage('No fue posible cancelar la venta: $error', isError: true);
    }
  }

  Future<bool> _cancelDaySale(Database db, int saleId) async {
    return db.transaction((txn) async {
      final sales = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (sales.isEmpty) return false;
      final sale = Map<String, dynamic>.from(sales.first);
      final currentStatus = (sale['status']?.toString().trim().toLowerCase() ?? '');
      const cancelledValues = {'cancelled', 'canceled', 'cancelado', 'cancelada', 'anulado', 'anulada'};
      if (cancelledValues.contains(currentStatus)) return false;
      final paid = currentStatus == 'paid' || currentStatus == 'pagado' || currentStatus == 'pagada';
      if (paid) {
        final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        for (final item in items) {
          final quantity = _toDouble(item['quantity']);
          final productId = _toInt(item['product_id']);
          if (quantity <= 0 || productId <= 0) continue;
          await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [quantity, productId]);
        }
      }
      await txn.update('sales', {'status': 'cancelled', 'sync_status': 'synced', 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [saleId]);
      await txn.delete('sync_outbox',
          where: 'uuid_local = ? AND status IN (?, ?)',
          whereArgs: [sale['uuid_local']?.toString() ?? '', 'queued', 'failed']);
      return true;
    });
  }

  Future<bool?> _showCancelDialog() => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancelar venta'),
      content: const Text('La venta será marcada como cancelada y el stock restaurado localmente.\n\nSi ya fue registrada en el servidor, se solicitará su anulación.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(false), child: const Text('No')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(true),
          child: const Text('Cancelar venta'),
        ),
      ],
    ),
  );

  // ============================================================
  // CÁLCULOS
  // ============================================================

  _SaleBusinessStatus _businessStatus(Map<String, dynamic> sale) {
    final raw = (sale['status'] ?? '').toString().trim().toLowerCase();
    switch (raw) {
      case 'cancelled': case 'canceled': case 'cancelado': case 'cancelada': case 'anulado': case 'anulada':
        return _SaleBusinessStatus.cancelled;
      case 'paid': case 'pagado': case 'pagada':
        return _SaleBusinessStatus.paid;
      default:
        return _SaleBusinessStatus.pending;
    }
  }

  String _statusLabel(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid: return 'Pagada';
      case _SaleBusinessStatus.pending: return 'Pendiente';
      case _SaleBusinessStatus.cancelled: return 'Cancelada';
    }
  }

  Color _statusColor(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid: return const Color(0xFF4CAF50);
      case _SaleBusinessStatus.pending: return Colors.orange;
      case _SaleBusinessStatus.cancelled: return Colors.red;
    }
  }

  bool _canCancel(Map<String, dynamic> sale) =>
      _businessStatus(sale) != _SaleBusinessStatus.cancelled;

  Iterable<Map<String, dynamic>> get _activeSales =>
      _sales.where((s) => _businessStatus(s) != _SaleBusinessStatus.cancelled);

  /// Total de ingresos = ventas activas + ingresos manuales del rango.
  double get _totalIngresos =>
      _activeSales.fold(0.0, (sum, s) => sum + _toDouble(s['total'])) +
      _ingresos.fold(0.0, (sum, i) => sum + i.monto);

  double get _totalEgresos => _egresos.fold(0.0, (sum, e) => sum + e.monto);
  double get _utilidadNeta => _totalIngresos - _totalEgresos;
  int get _transacciones => _activeSales.length;

  /// Extrae el método de pago principal de una venta de forma segura.
  /// Prioridad: payments[0].method → payment_method → 'Efectivo'
  String _metodoVenta(Map<String, dynamic> sale) {
    // La BD del día guarda los pagos en una tabla separada, no en la fila.
    // La BD del historial guarda payment_method como columna directa.
    final direct = sale['payment_method']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    return 'Efectivo';
  }

  /// Desglose de ingresos por método de pago.
  Map<String, double> get _ingresoPorMetodo {
    final map = <String, double>{};
    for (final sale in _activeSales) {
      final method = _metodoVenta(sale);
      final total = _toDouble(sale['total']);
      map[method] = (map[method] ?? 0) + total;
    }
    return map;
  }

  /// Efectivo esperado en caja = suma de ventas pagadas con método Efectivo.
  double get _efectivoEnCaja {
    double total = 0;
    for (final sale in _activeSales) {
      final method = _metodoVenta(sale).toLowerCase();
      if (method.contains('efectivo') || method == 'cash') {
        total += _toDouble(sale['total']);
      }
    }
    return total;
  }

  /// Total de métodos distintos a efectivo.
  double get _otrosMetodos {
    double total = 0;
    for (final sale in _activeSales) {
      final method = _metodoVenta(sale).toLowerCase();
      if (!method.contains('efectivo') && method != 'cash') {
        total += _toDouble(sale['total']);
      }
    }
    return total;
  }

  // ============================================================
  // BÚSQUEDA — elementos combinados
  // ============================================================

  /// Lista combinada de ventas + egresos filtrada por búsqueda.
  /// Cada elemento tiene un campo `_type`: 'sale' o 'egreso'.
  List<dynamic> get _filteredItems {
    final q = _searchQuery.toLowerCase();

    final ventas = _sales.where((s) {
      if (q.isEmpty) return true;
      final folio = (s['folio'] ?? s['id'] ?? '').toString().toLowerCase();
      final method = _metodoVenta(s).toLowerCase();
      return folio.contains(q) || method.contains(q);
    }).toList();

    final egresos = _egresos.where((e) {
      if (q.isEmpty) return true;
      return e.concepto.toLowerCase().contains(q) ||
          (e.formaPago?.toLowerCase().contains(q) ?? false);
    }).toList();

    final ingresosM = _ingresos.where((i) {
      if (q.isEmpty) return true;
      return i.concepto.toLowerCase().contains(q) ||
          (i.formaPago?.toLowerCase().contains(q) ?? false);
    }).toList();

    final combined = <dynamic>[...ventas, ...egresos, ...ingresosM];
    combined.sort((a, b) {
      DateTime dateA, dateB;
      if (a is Map) {
        dateA = _dateValue(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else if (a is _Egreso) {
        dateA = a.registradoAt;
      } else {
        dateA = (a as _Ingreso).registradoAt;
      }
      if (b is Map) {
        dateB = _dateValue(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      } else if (b is _Egreso) {
        dateB = b.registradoAt;
      } else {
        dateB = (b as _Ingreso).registradoAt;
      }
      return dateB.compareTo(dateA);
    });
    return combined;
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  DateTime? _dateValue(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--/--/---- --:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ));
  }

  // ============================================================
  // MENÚ REGISTRO — ingreso o egreso
  // ============================================================

  Future<void> _mostrarMenuMovimiento() async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Registrar movimiento',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_circle_up_outlined, color: Colors.green.shade700),
                ),
                title: const Text('Registrar ingreso',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Depósito, cobro, entrada de efectivo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _agregarIngreso();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_circle_down_outlined, color: Colors.red.shade700),
                ),
                title: const Text('Registrar egreso',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Gasto, retiro, salida de efectivo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _agregarEgreso();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHighest,
        elevation: 0,
        title: Text(
          _companyName.isNotEmpty ? _companyName.toUpperCase() : 'ESTADÍSTICAS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: cs.onSurface,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── SELECTOR DE RANGO ──────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _buildDateRangeRow(),
                    ),
                  ),

                  // ── FECHA SELECCIONADA ─────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text(
                        _formatDate(_fechaInicio),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),

                  // ── TOTAL CENTRAL ──────────────────────────────
                  SliverToBoxAdapter(child: _buildTotalCentral(cs)),

                  // ── DESGLOSE INGRESOS / EGRESOS ────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildIngresosEgresos(cs),
                    ),
                  ),

                  // ── DESGLOSE POR MÉTODO DE PAGO ────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildDesgloseMetodos(cs),
                    ),
                  ),

                  // ── EFECTIVO EN CAJA / OTROS ───────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildCajaRow(cs),
                    ),
                  ),

                  // ── BARRA DE BÚSQUEDA ──────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _buildSearchBar(cs),
                    ),
                  ),

                  // ── LISTA COMBINADA ────────────────────────────
                  if (_filteredItems.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        child: _buildEmptyState(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildListItem(_filteredItems[i]),
                          ),
                          childCount: _filteredItems.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarMenuMovimiento,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ============================================================
  // WIDGETS DE UI
  // ============================================================

  /// Selector de rango de fechas (Fecha Inicio / Fecha Fin).
  Widget _buildDateRangeRow() {
    return Row(
      children: [
        Expanded(child: _DateButton(
          label: 'Fecha Inicio',
          date: _fechaInicio,
          onTap: () => _seleccionarFecha(esInicio: true),
        )),
        const SizedBox(width: 10),
        Expanded(child: _DateButton(
          label: 'Fecha Fin',
          date: _fechaFin,
          onTap: () => _seleccionarFecha(esInicio: false),
        )),
        const SizedBox(width: 10),
        // Botón PDF/exportar (próximamente)
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  /// TOTAL grande centrado.
  Widget _buildTotalCentral(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('TOTAL',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(
            '\$${_utilidadNeta.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: _utilidadNeta >= 0 ? cs.onSurface : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// Fila Ingresos | Egresos lado a lado.
  Widget _buildIngresosEgresos(ColorScheme cs) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Text('Ingresos',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade700)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '\$${_totalIngresos.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.green.shade700),
                    ),
                  ),
                  if (_transacciones > 0) ...[
                    const SizedBox(height: 2),
                    Text('$_transacciones venta(s)',
                        style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                  ],
                  if (_ingresos.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text('+ ${_ingresos.length} ingreso(s) manual(es)',
                        style: TextStyle(fontSize: 10, color: Colors.green.shade500)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Text('Egresos',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '\$${_totalEgresos.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.red.shade700),
                    ),
                  ),
                  if (_egresos.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('${_egresos.length} egreso(s)',
                        style: TextStyle(fontSize: 10, color: Colors.red.shade400)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Desglose de ingresos por método de pago.
  Widget _buildDesgloseMetodos(ColorScheme cs) {
    final metodos = _ingresoPorMetodo;
    if (metodos.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Desglose por método de pago',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          ...metodos.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(_iconMetodo(e.key), size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.key,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                    Text('\$${e.value.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Fila de efectivo esperado en caja vs otros métodos.
  Widget _buildCajaRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            icon: Icons.savings_outlined,
            label: 'Efectivo en caja',
            value: '\$${_efectivoEnCaja.toStringAsFixed(2)}',
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.credit_card_outlined,
            label: 'Otros métodos',
            value: '\$${_otrosMetodos.toStringAsFixed(2)}',
            color: cs.secondary,
          ),
        ),
      ],
    );
  }

  /// Barra de búsqueda.
  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Buscar venta, ingreso o egreso...',
          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  /// Ítem de la lista — venta o egreso.
  Widget _buildListItem(dynamic item) {
    if (item is _Egreso) return _buildEgresoTile(item);
    if (item is _Ingreso) return _buildIngresoTile(item);
    return _buildSaleTile(item as Map<String, dynamic>);
  }

  Widget _buildSaleTile(Map<String, dynamic> sale) {
    final folio = sale['folio']?.toString().trim() ?? '';
    final saleId = sale['id']?.toString() ?? '-';
    final title = folio.isNotEmpty ? folio : 'Venta $saleId';
    final total = _toDouble(sale['total']);
    final method = _metodoVenta(sale);
    final statusColor = _statusColor(sale);
    final statusLabel = _statusLabel(sale);
    final fechaHora = _formatDateTime(sale['created_at']?.toString());

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openSale(sale),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Indicador de color izquierdo
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_iconMetodo(method), size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(method,
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 8),
                        Text(fechaHora,
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('\$${total.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ),
                ],
              ),
              if (_canCancel(sale)) ...[
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Cancelar venta',
                  onPressed: () => _cancelSale(sale),
                  icon: Icon(Icons.cancel_outlined, size: 18, color: Colors.red.shade400),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEgresoTile(_Egreso e) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.concepto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_downward, size: 12, color: Colors.red.shade400),
                      const SizedBox(width: 4),
                      Text(e.formaPago ?? 'Egreso',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade500)),
                      const SizedBox(width: 8),
                      Text(_formatDateTime(e.registradoAt.toIso8601String()),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('- \$${e.monto.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade700)),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _confirmarEliminarEgreso(e),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminarEgreso(_Egreso e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar egreso'),
        content: Text('¿Eliminar "${e.concepto}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) await _eliminarEgreso(e.id);
  }

  Widget _buildIngresoTile(_Ingreso i) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.concepto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.arrow_upward, size: 12, color: Colors.green.shade400),
                      const SizedBox(width: 4),
                      Text(i.formaPago ?? 'Ingreso manual',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                      const SizedBox(width: 8),
                      Text(_formatDateTime(i.registradoAt.toIso8601String()),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('+ \$${i.monto.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.green.shade700)),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _confirmarEliminarIngreso(i),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 18, color: Colors.green.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEliminarIngreso(_Ingreso i) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ingreso'),
        content: Text('¿Eliminar "${i.concepto}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) await _eliminarIngreso(i.id);
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 58, color: Colors.black26),
          SizedBox(height: 14),
          Text('Sin registros en este rango de fechas',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Las ventas y egresos del rango seleccionado aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  IconData _iconMetodo(String method) {
    final m = method.toLowerCase();
    if (m.contains('efectivo') || m == 'cash') return Icons.payments_outlined;
    if (m.contains('tarjeta') || m.contains('card') || m.contains('crédito') || m.contains('débito')) {
      return Icons.credit_card_outlined;
    }
    if (m.contains('transfer')) return Icons.swap_horiz;
    if (m.contains('cheque') || m.contains('check')) return Icons.receipt_outlined;
    return Icons.attach_money;
  }
}

// ============================================================
// TIPO DE MOVIMIENTO
// ============================================================

enum _TipoMovimiento { ingreso, egreso }

// ============================================================
// DIÁLOGO GENÉRICO DE MOVIMIENTO (ingreso o egreso)
// ============================================================

class _MovimientoDialog extends StatefulWidget {
  const _MovimientoDialog({required this.tipo, required this.onGuardar});
  final _TipoMovimiento tipo;
  final Future<void> Function(String concepto, double monto, String? formaPago) onGuardar;

  @override
  State<_MovimientoDialog> createState() => _MovimientoDialogState();
}

class _MovimientoDialogState extends State<_MovimientoDialog> {
  final TextEditingController _conceptoCtrl = TextEditingController();
  final TextEditingController _montoCtrl = TextEditingController();
  String? _formaPago;
  bool _guardando = false;
  String? _error;

  static const _formasPago = ['Efectivo', 'Tarjeta', 'Transferencia', 'Otro'];

  bool get _esEgreso => widget.tipo == _TipoMovimiento.egreso;

  @override
  void dispose() {
    _conceptoCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final concepto = _conceptoCtrl.text.trim();
    final montoStr = _montoCtrl.text.trim();
    if (concepto.isEmpty) { setState(() => _error = 'Ingresa un concepto.'); return; }
    final monto = double.tryParse(montoStr);
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresa un monto válido mayor a 0.');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.onGuardar(concepto, monto, _formaPago);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _esEgreso ? Colors.red.shade700 : Colors.green.shade700;
    final icon = _esEgreso
        ? Icons.arrow_circle_down_outlined
        : Icons.arrow_circle_up_outlined;
    final titulo = _esEgreso ? 'Registrar egreso' : 'Registrar ingreso';
    final hint = _esEgreso
        ? 'Ej. Gasolina, Insumos, Limpieza'
        : 'Ej. Depósito, Cobro, Transferencia recibida';

    return AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(titulo),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _conceptoCtrl,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Concepto *',
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _montoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Monto *',
              prefixText: '\$',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
            onSubmitted: (_) => _guardar(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _formaPago,
            decoration: const InputDecoration(
              labelText: 'Forma de pago (opcional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('Sin especificar')),
              ..._formasPago.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))),
            ],
            onChanged: (v) => setState(() => _formaPago = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _guardando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================
// WIDGETS AUXILIARES
// ============================================================

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  Text('$day/$month/$year', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _SaleBusinessStatus { paid, pending, cancelled }
