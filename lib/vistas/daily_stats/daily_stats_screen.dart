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
// PANTALLA
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
      final sales = await _loadAllTodaySales();
      final egresos = await _loadEgresos();
      if (!mounted) return;
      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _egresos = egresos;
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
      final sales = await _loadAllTodaySales();
      final egresos = await _loadEgresos();
      if (!mounted) return;
      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _egresos = egresos;
        _loading = false;
      });
    } catch (_) {}
    finally {
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
  // EGRESOS — CRUD LOCAL EN SQLITE (tabla en LocalDb)
  // ============================================================

  /// Carga los egresos del día desde la tabla `daily_expenses` de la BD local.
  Future<List<_Egreso>> _loadEgresos() async {
    try {
      final db = await _historyDb.database;
      // Crear tabla si no existe aún (migración en caliente)
      await db.execute('''CREATE TABLE IF NOT EXISTS daily_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        concepto TEXT NOT NULL,
        monto REAL NOT NULL,
        forma_pago TEXT,
        registrado_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');

      final hoy = DateTime.now();
      final inicio = DateTime(hoy.year, hoy.month, hoy.day).toIso8601String();
      final fin = DateTime(hoy.year, hoy.month, hoy.day, 23, 59, 59).toIso8601String();

      final rows = await db.query(
        'daily_expenses',
        where: "registrado_at >= ? AND registrado_at <= ?",
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

  Future<void> _guardarEgreso({
    required String concepto,
    required double monto,
    String? formaPago,
  }) async {
    final db = await _historyDb.database;
    final now = DateTime.now().toIso8601String();
    final uuid = 'egreso_${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('daily_expenses', {
      'uuid': uuid,
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

  /// Abre el modal para registrar un nuevo egreso.
  Future<void> _agregarEgreso() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EgresoDialog(
        onGuardar: (concepto, monto, formaPago) async {
          Navigator.of(ctx).pop();
          await _guardarEgreso(concepto: concepto, monto: monto, formaPago: formaPago);
        },
      ),
    );
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
      await _syncService.syncPendingSales(companyId: companyId, userId: userId, businessDate: DateTime.now());
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
  // VENTAS
  // ============================================================

  Future<List<Map<String, dynamic>>> _loadAllTodaySales() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;
    final historySales = await _historyDb.getTodaySales();
    List<Map<String, dynamic>> daySales = [];
    if (companyId > 0 && userId > 0) {
      try {
        daySales = await _dayDb.getTodaySales(
          companyId: companyId, userId: userId, businessDate: DateTime.now(),
        );
      } catch (_) {}
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
      final currentUpdated = _dateValue(current['updated_at']);
      final historyUpdated = _dateValue(sale['updated_at']);
      if (historyUpdated != null && (currentUpdated == null || historyUpdated.isAfter(currentUpdated))) {
        unique[uuid] = sale; continue;
      }
      if ((historyUpdated == null && currentUpdated == null) ||
          (historyUpdated != null && currentUpdated != null && historyUpdated.isAtSameMomentAs(currentUpdated))) {
        final currentSync = current['sync_status']?.toString().toLowerCase() ?? '';
        final historySync = sale['sync_status']?.toString().toLowerCase() ?? '';
        if (historySync == 'synced' && currentSync != 'synced') unique[uuid] = sale;
      }
    }

    final result = unique.values.toList();
    result.sort((a, b) {
      final dateA = _dateValue(a['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = _dateValue(b['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });
    return result;
  }

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
      if (mounted) _showMessage(serverId > 0 ? 'Venta cancelada correctamente.' : 'Venta cancelada localmente. No se enviará al servidor.');
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
      const cancelledValues = {'cancelled','canceled','cancelado','cancelada','anulado','anulada'};
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
      await txn.update('sales', {'status': 'cancelled', 'sync_status': 'synced', 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [saleId]);
      await txn.delete('sync_outbox', where: 'uuid_local = ? AND status IN (?, ?)', whereArgs: [sale['uuid_local']?.toString() ?? '', 'queued', 'failed']);
      return true;
    });
  }

  Future<bool?> _showCancelDialog() => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancelar venta'),
      content: const Text('La venta será marcada como cancelada y el stock será restaurado localmente.\n\nSi la venta ya fue registrada en el servidor, primero se solicitará su anulación.'),
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
  // UTILIDADES
  // ============================================================

  _SaleBusinessStatus _businessStatus(Map<String, dynamic> sale) {
    final raw = (sale['status'] ?? '').toString().trim().toLowerCase();
    switch (raw) {
      case 'cancelled': case 'canceled': case 'cancelado': case 'cancelada': case 'anulado': case 'anulada':
        return _SaleBusinessStatus.cancelled;
      case 'paid': case 'pagado': case 'pagada':
        return _SaleBusinessStatus.paid;
      default: return _SaleBusinessStatus.pending;
    }
  }

  String _statusText(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid: return 'Pagada';
      case _SaleBusinessStatus.pending: return 'Pendiente';
      case _SaleBusinessStatus.cancelled: return 'Cancelada';
    }
  }

  Color _statusColor(Map<String, dynamic> sale) {
    switch (_businessStatus(sale)) {
      case _SaleBusinessStatus.paid: return Colors.green;
      case _SaleBusinessStatus.pending: return Colors.orange;
      case _SaleBusinessStatus.cancelled: return Colors.red;
    }
  }

  bool _canCancel(Map<String, dynamic> sale) => _businessStatus(sale) != _SaleBusinessStatus.cancelled;

  Iterable<Map<String, dynamic>> get _activeSales =>
      _sales.where((s) => _businessStatus(s) != _SaleBusinessStatus.cancelled);

  double get _total => _activeSales.fold(0, (sum, s) => sum + _saleTotal(s));
  int get _transacciones => _activeSales.length;
  double get _ticketPromedio => _transacciones == 0 ? 0 : _total / _transacciones;
  int get _pendingSales => _sales.where((s) => _businessStatus(s) == _SaleBusinessStatus.pending).length;
  int get _cancelledSales => _sales.where((s) => _businessStatus(s) == _SaleBusinessStatus.cancelled).length;
  double get _totalEgresos => _egresos.fold(0, (sum, e) => sum + e.monto);

  double _saleTotal(Map<String, dynamic> sale) => _toDouble(sale['total']);

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
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--/--/---- --:--';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$day/$month/${date.year} $hour:$minute';
    } catch (_) { return isoString; }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 3),
    ));
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas del día'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildStatsHorizontal(),
                  const SizedBox(height: 16),
                  // ── CARD EGRESOS (roja) ──────────────────────────
                  _buildEgresosCard(),
                  const SizedBox(height: 16),
                  // ── UTILIDAD NETA ────────────────────────────────
                  _buildUtilidadNeta(),
                  const SizedBox(height: 24),
                  _buildSalesHeader(),
                  const SizedBox(height: 10),
                  if (_sales.isEmpty)
                    _buildEmptyState()
                  else
                    ..._sales.map((sale) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SaleCard(
                        sale: sale,
                        total: _saleTotal(sale),
                        status: _statusText(sale),
                        statusColor: _statusColor(sale),
                        canCancel: _canCancel(sale),
                        onTap: () => _openSale(sale),
                        onCancel: () => _cancelSale(sale),
                        formatDateTime: _formatDateTime,
                      ),
                    )),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarEgreso,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Registrar egreso'),
      ),
    );
  }

  // ============================================================
  // WIDGETS
  // ============================================================

  Widget _buildStatsHorizontal() {
    return SizedBox(
      height: 125,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _StatCard(icon: Icons.attach_money, label: 'Total ingresos', value: '\$${_total.toStringAsFixed(2)}'),
            const SizedBox(width: 12),
            // Clarificado: "Transacciones del día" en lugar de "Tickets"
            _StatCard(icon: Icons.receipt_long_outlined, label: 'Transacciones', value: '$_transacciones',
                subtitle: 'ventas del día'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.analytics_outlined, label: 'Ticket promedio', value: '\$${_ticketPromedio.toStringAsFixed(2)}',
                subtitle: 'promedio por venta'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.sync_problem_outlined, label: 'Pendientes', value: '$_pendingSales'),
            const SizedBox(width: 12),
            _StatCard(icon: Icons.cancel_outlined, label: 'Canceladas', value: '$_cancelledSales'),
          ],
        ),
      ),
    );
  }

  /// Card de egresos del día en color rojo.
  Widget _buildEgresosCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.red.shade100, shape: BoxShape.circle),
                child: Icon(Icons.arrow_circle_down_outlined, color: Colors.red.shade700, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Egresos del día',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.red.shade800)),
              ),
              Text('\$${_totalEgresos.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
            ],
          ),
          if (_egresos.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ..._egresos.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.concepto, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (e.formaPago != null)
                          Text(e.formaPago!, style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ],
                    ),
                  ),
                  Text('\$${e.monto.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _confirmarEliminarEgreso(e),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                    ),
                  ),
                ],
              ),
            )),
          ] else ...[
            const SizedBox(height: 8),
            Text('Sin egresos registrados hoy.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
          ],
        ],
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
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _eliminarEgreso(e.id);
  }

  Widget _buildUtilidadNeta() {
    final utilidad = _total - _totalEgresos;
    final positivo = utilidad >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: positivo ? const Color(0xFF9AC53B).withAlpha(22) : Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: positivo ? const Color(0xFF9AC53B).withAlpha(60) : Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(positivo ? Icons.trending_up : Icons.trending_down,
              color: positivo ? const Color(0xFF58751F) : Colors.red.shade700),
          const SizedBox(width: 10),
          const Text('Utilidad neta del día',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            '\$${utilidad.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: positivo ? const Color(0xFF58751F) : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text('Ventas del día', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        ),
        if (_sales.isNotEmpty)
          Text('${_sales.length} ${_sales.length == 1 ? 'venta' : 'ventas'}',
              style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.grey.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 58, color: Colors.black26),
          SizedBox(height: 14),
          Text('No hay ventas registradas hoy', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('Las ventas realizadas aparecerán aquí.', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

// ============================================================
// DIÁLOGO DE EGRESO
// ============================================================

class _EgresoDialog extends StatefulWidget {
  const _EgresoDialog({required this.onGuardar});
  final Future<void> Function(String concepto, double monto, String? formaPago) onGuardar;

  @override
  State<_EgresoDialog> createState() => _EgresoDialogState();
}

class _EgresoDialogState extends State<_EgresoDialog> {
  final TextEditingController _conceptoCtrl = TextEditingController();
  final TextEditingController _montoCtrl = TextEditingController();
  String? _formaPago;
  bool _guardando = false;
  String? _error;

  static const _formasPago = ['Efectivo', 'Tarjeta', 'Transferencia', 'Otro'];

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
    if (monto == null || monto <= 0) { setState(() => _error = 'Ingresa un monto válido mayor a 0.'); return; }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.onGuardar(concepto, monto, _formaPago);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.arrow_circle_down_outlined, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Text('Registrar egreso'),
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
            decoration: const InputDecoration(
              labelText: 'Concepto *',
              hintText: 'Ej. Gasolina, Insumos, Limpieza',
              border: OutlineInputBorder(),
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
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================
// ENUMS Y WIDGETS AUXILIARES
// ============================================================

enum _SaleBusinessStatus { paid, pending, cancelled }

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.total,
    required this.status,
    required this.statusColor,
    required this.canCancel,
    required this.onTap,
    required this.onCancel,
    required this.formatDateTime,
  });

  final Map<String, dynamic> sale;
  final double total;
  final String status;
  final Color statusColor;
  final bool canCancel;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final String Function(String?) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final saleId = sale['id']?.toString() ?? '-';
    final folio = sale['folio']?.toString().trim();
    final fechaHora = formatDateTime(sale['created_at']?.toString());

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMainInfo(saleId, folio, fechaHora),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text('\$${total.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        ),
                        if (canCancel)
                          OutlinedButton.icon(
                            onPressed: onCancel,
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                          ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _buildMainInfo(saleId, folio, fechaHora)),
                  const SizedBox(width: 16),
                  Text('\$${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  if (canCancel) ...[
                    const SizedBox(width: 8),
                    IconButton(tooltip: 'Cancelar venta', onPressed: onCancel, icon: const Icon(Icons.cancel_outlined), color: Colors.red),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainInfo(String saleId, String? folio, String fechaHora) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF9AC53B).withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.receipt_long_outlined, color: Color(0xFF58751F)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(folio != null && folio.isNotEmpty ? 'Venta $folio' : 'Venta $saleId',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(fechaHora, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 175,
      constraints: const BoxConstraints(minHeight: 115, maxHeight: 130),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF9AC53B).withAlpha(25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF9AC53B).withAlpha(45)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF9AC53B).withAlpha(35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF58751F)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.black38)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
