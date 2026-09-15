import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/database/pos_db_service.dart';
import '../../core/models/sale_model.dart';
import '../../core/services/sync_service.dart';
import '../../core/storage/app_storage.dart';
import '../ventas/sale_detail_screen.dart';

// ============================================================
// PANTALLA PRINCIPAL
// ============================================================

class DailyStatsScreen extends StatefulWidget {
  const DailyStatsScreen({super.key});

  @override
  State<DailyStatsScreen> createState() => _DailyStatsScreenState();
}

class _DailyStatsScreenState extends State<DailyStatsScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final LocalDb _historyDb = LocalDb();
  final PosDatabaseService _dayDb = PosDatabaseService();
  final SyncService _syncService = SyncService();

  StreamSubscription<void>? _salesChangesSubscription;

  bool _refreshQueued = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _syncing = false;

  List<Map<String, dynamic>> _sales = const [];

  late TabController _tabController;

  // ============================================================
  // ESTADO DEL DÍA
  // ============================================================

  String _companyName = '';

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

  List<Map<String, dynamic>> _topProductos = const [];
  Map<String, List<Map<String, dynamic>>> _topPorDia = const {};

  // ============================================================
  // ESTADO DEL MES
  // ============================================================

  bool _loadingMes = true;

  double _mesTotal = 0;
  int _mesTransacciones = 0;
  double _mesTicketPromedio = 0;
  List<Map<String, dynamic>> _mesPorDia = const [];
  List<Map<String, dynamic>> _mesTopProductos = const [];
  Map<String, List<Map<String, dynamic>>> _mesTopPorDia = const {};

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _tabController.addListener(() {
      if (_tabController.index == 1 && _loadingMes) {
        _loadMonthStats();
      }
    });

    WidgetsBinding.instance.addObserver(this);

    _salesChangesSubscription = LocalDb.salesChanges.listen((_) {
      if (!mounted || _syncing) return;

      if (_refreshing) {
        _refreshQueued = true;
        return;
      }

      _refreshQueued = false;
      _refreshSilently();
    });

    _initialize();
  }

  @override
  void dispose() {
    _salesChangesSubscription?.cancel();
    _salesChangesSubscription = null;

    _tabController.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_syncing) {
      _syncAndRefreshOnResume();
    }
  }

  // ============================================================
  // INICIALIZACIÓN
  // ============================================================

  Future<void> _initialize() async {
    final name = await AppStorage().getCompanyName();

    if (mounted) {
      setState(() => _companyName = name ?? '');
    }

    await _loadStats();

    if (!mounted) return;

    try {
      final offline = await AppStorage().isOfflineSession();

      if (!offline) {
        await _syncUploadThenPull();

        if (mounted) {
          await _loadStats();
        }
      }
    } catch (e) {
      debugPrint('ℹ️ Pull inicial no disponible: $e');
    }
  }

  Future<void> _syncAndRefreshOnResume() async {
    try {
      final offline = await AppStorage().isOfflineSession();

      if (!offline) {
        await _syncUploadThenPull();
      }
    } catch (_) {}

    if (mounted) {
      await _refreshSilently();
    }
  }

  // ============================================================
  // CARGA
  // ============================================================

  Future<void> _loadStats() async {
    if (!mounted || _refreshing) return;

    _refreshing = true;

    try {
      final sales = await _loadSalesInRange();

      final top = await _loadTopProductos();
      final topPorDia = await _loadTopProductosPorDia();

      if (!mounted) return;

      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _topProductos = top;
        _topPorDia = topPorDia;
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

      final top = await _loadTopProductos();
      final topPorDia = await _loadTopProductosPorDia();

      if (!mounted) return;

      setState(() {
        _sales = List<Map<String, dynamic>>.from(sales);
        _topProductos = top;
        _topPorDia = topPorDia;
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
      if (mounted && !_syncing && !_refreshing) {
        _refreshSilently();
      }
    });
  }

  // ============================================================
  // VENTAS EN RANGO
  // ============================================================

  Future<List<Map<String, dynamic>>> _loadSalesInRange() async {
    final inicioClave = _dayDb.dateKey(_fechaInicio);
    final finClave = _dayDb.dateKey(_fechaFin);
    final esHoy = inicioClave == _dayDb.dateKey(DateTime.now());

    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    List<Map<String, dynamic>> historySales;

    try {
      if (esHoy) {
        historySales = await _historyDb.getTodaySales();
      } else {
        historySales = await _historyDb.getSales(businessDate: inicioClave);

        if (inicioClave != finClave) {
          historySales = await _historyDb.getSales();
        }
      }
    } catch (_) {
      historySales = [];
    }

    List<Map<String, dynamic>> daySales = [];

    if (companyId > 0 && userId > 0 && esHoy) {
      try {
        daySales = await _dayDb.getTodaySales(
          companyId: companyId,
          userId: userId,
          businessDate: DateTime.now(),
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

      if (uuid.isEmpty) {
        unique['history-${sale['id']}'] = sale;
        continue;
      }

      if (!unique.containsKey(uuid)) {
        unique[uuid] = sale;
        continue;
      }

      final current = unique[uuid]!;

      final cUpdated = _dateValue(current['updated_at']);
      final hUpdated = _dateValue(sale['updated_at']);

      if (hUpdated != null &&
          (cUpdated == null || hUpdated.isAfter(cUpdated))) {
        unique[uuid] = sale;
        continue;
      }

      if ((hUpdated == null && cUpdated == null) ||
          (hUpdated != null &&
              cUpdated != null &&
              hUpdated.isAtSameMomentAs(cUpdated))) {
        if ((sale['sync_status']?.toString().toLowerCase() ?? '') == 'synced' &&
            (current['sync_status']?.toString().toLowerCase() ?? '') !=
                'synced') {
          unique[uuid] = sale;
        }
      }
    }

    final result = unique.values.where((s) {
      DateTime? dt = _dateValue(s['created_at']);
      dt ??= _dateValue(s['paid_at']);

      if (dt == null) {
        final bd = s['business_date']?.toString().trim() ?? '';
        if (bd.isNotEmpty) {
          dt = DateTime.tryParse(bd);
        }
      }

      if (dt == null) return true;

      return !dt.isBefore(_fechaInicio) && !dt.isAfter(_fechaFin);
    }).toList();

    result.sort((a, b) {
      final dateA =
          _dateValue(a['created_at']) ??
          _dateValue(a['paid_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final dateB =
          _dateValue(b['created_at']) ??
          _dateValue(b['paid_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      return dateB.compareTo(dateA);
    });

    return result;
  }

  // ============================================================
  // TOP PRODUCTOS (LOCAL)
  // ============================================================

  Future<List<Map<String, dynamic>>> _loadTopProductos() async {
    try {
      return await _historyDb.getTopProductsLocal(
        desde: _fechaInicio,
        hasta: _fechaFin,
        limite: 10,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  _loadTopProductosPorDia() async {
    try {
      return await _historyDb.getTopProductsByDayLocal(
        desde: _fechaInicio,
        hasta: _fechaFin,
        limitePorDia: 5,
      );
    } catch (_) {
      return const {};
    }
  }

  // ============================================================
  // MES
  // ============================================================

  Future<void> _loadMonthStats() async {
    final ahora = DateTime.now();

    final inicio = DateTime(ahora.year, ahora.month, 1);
    final fin = DateTime(
      ahora.year,
      ahora.month,
      DateTime(ahora.year, ahora.month + 1, 0).day,
      23,
      59,
      59,
    );

    try {
      final salesMes = await _loadSalesForRange(inicio, fin);

      final activas = salesMes.where((s) {
        final raw = (s['status'] ?? '').toString().trim().toLowerCase();

        return raw != 'cancelled' &&
            raw != 'canceled' &&
            raw != 'cancelado' &&
            raw != 'cancelada' &&
            raw != 'anulado' &&
            raw != 'anulada';
      }).toList();

      double total = 0;

      for (final s in activas) {
        total += _toDouble(s['total']);
      }

      final tickets = activas.length;

      final promedio = tickets > 0 ? total / tickets : 0.0;

      final ventasPorDia = <Map<String, dynamic>>[];

      for (final s in activas) {
        final createdAt =
            s['created_at']?.toString() ?? s['paid_at']?.toString() ?? '';

        if (createdAt.isEmpty) continue;

        final fecha = createdAt.substring(0, 10);

        final index = ventasPorDia.indexWhere((v) => v['fecha'] == fecha);

        if (index == -1) {
          ventasPorDia.add({
            'fecha': fecha,
            'dia': _formatearDiaMes(fecha),
            'cantidad': 1,
            'total': _toDouble(s['total']),
          });
        } else {
          ventasPorDia[index]['cantidad'] =
              (ventasPorDia[index]['cantidad'] as int) + 1;

          ventasPorDia[index]['total'] =
              (ventasPorDia[index]['total'] as double) + _toDouble(s['total']);
        }
      }

      ventasPorDia.sort(
        (a, b) => a['fecha'].toString().compareTo(b['fecha'].toString()),
      );

      final top = await _historyDb.getTopProductsLocal(
        desde: inicio,
        hasta: fin,
        limite: 10,
      );

      final topPorDia = await _historyDb.getTopProductsByDayLocal(
        desde: inicio,
        hasta: fin,
        limitePorDia: 5,
      );

      if (!mounted) return;

      setState(() {
        _mesTotal = total;
        _mesTransacciones = tickets;
        _mesTicketPromedio = promedio;
        _mesPorDia = ventasPorDia;
        _mesTopProductos = top;
        _mesTopPorDia = topPorDia;
        _loadingMes = false;
      });
    } catch (error) {
      debugPrint('❌ Error estadísticas mes: $error');

      if (!mounted) return;
      setState(() => _loadingMes = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadSalesForRange(
    DateTime desde,
    DateTime hasta,
  ) async {
    try {
      final all = await _historyDb.getSales();

      final result = <Map<String, dynamic>>[];

      for (final raw in all) {
        final s = Map<String, dynamic>.from(raw);

        DateTime? dt = _dateValue(s['created_at']);
        dt ??= _dateValue(s['paid_at']);

        if (dt == null) {
          final bd = s['business_date']?.toString().trim() ?? '';
          if (bd.isNotEmpty) dt = DateTime.tryParse(bd);
        }

        if (dt == null) continue;
        if (dt.isBefore(desde) || dt.isAfter(hasta)) continue;

        result.add(s);
      }

      return result;
    } catch (_) {
      return const [];
    }
  }

  // ============================================================
  // SYNC
  // ============================================================

  Future<void> _syncUploadThenPull() async {
    final companyId = await AppStorage().getEmpresaId() ?? 0;
    final userId = await AppStorage().getUserId() ?? 0;

    if (companyId <= 0 || userId <= 0) {
      throw Exception('No existe una sesión válida para sincronizar.');
    }

    final result = await _syncService.syncManual(
      companyId: companyId,
      userId: userId,
      businessDate: DateTime.now(),
    );

    if (result.failed > 0) {
      throw Exception(
        'No se completó la sincronización porque '
        '${result.failed} operación(es) fallaron.',
      );
    }
  }

  Future<void> _syncNow() async {
    if (!mounted || _syncing) return;

    setState(() => _syncing = true);

    try {
      await _syncUploadThenPull();

      if (mounted) await _loadStats();

      if (mounted) _showMessage('Sincronización completada.');
    } catch (error) {
      if (mounted) {
        _showMessage('No fue posible sincronizar: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);

      await _refreshSilently();
    }
  }

  // ============================================================
  // VENTA (detalle)
  // ============================================================

  Future<void> _openSale(Map<String, dynamic> sale) async {
    if (!mounted) return;

    final saleId = _toInt(sale['id']);

    if (saleId <= 0) {
      _showMessage('No se pudo identificar la venta.', isError: true);
      return;
    }

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

        if (companyId <= 0 || userId <= 0) {
          throw Exception('No existe una sesión válida.');
        }

        final db = await _dayDb.open(
          companyId: companyId,
          userId: userId,
          businessDate: DateTime.now(),
        );

        items = await _dayDb.getSaleItems(db, saleId);
        payments = await _dayDb.getSalePayments(db, saleId);
      }

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            sale: SaleModel.fromMap(
              Map<String, dynamic>.from(sale),
              saleItems: items.map(SaleItemModel.fromMap).toList(),
              salePayments: payments.map(SalePaymentModel.fromMap).toList(),
            ),
          ),
        ),
      );

      if (mounted) await _refreshSilently();
    } catch (error) {
      if (mounted) {
        _showMessage('No fue posible abrir la venta: $error', isError: true);
      }
    }
  }

  // ============================================================
  // CÁLCULOS DEL DÍA
  // ============================================================

  Iterable<Map<String, dynamic>> get _activeSales => _sales.where((s) {
    final raw = (s['status'] ?? '').toString().trim().toLowerCase();

    return raw != 'cancelled' &&
        raw != 'canceled' &&
        raw != 'cancelado' &&
        raw != 'cancelada' &&
        raw != 'anulado' &&
        raw != 'anulada';
  });

  double get _totalVentas =>
      _activeSales.fold(0.0, (sum, s) => sum + _toDouble(s['total']));

  int get _numeroTickets => _activeSales.length;

  double get _ticketPromedio =>
      _numeroTickets > 0 ? _totalVentas / _numeroTickets : 0.0;

  double get _totalImpuestos =>
      _activeSales.fold(0.0, (sum, s) => sum + _toDouble(s['impuesto_global']));

  Map<int, Map<String, double>> get _ventasPorHora {
    final map = <int, Map<String, double>>{};

    for (var i = 0; i < 24; i++) {
      map[i] = {'cantidad': 0, 'total': 0};
    }

    for (final s in _activeSales) {
      final dt = _dateValue(s['created_at']) ?? _dateValue(s['paid_at']);

      if (dt == null) continue;

      final hora = dt.hour;
      final entry = map[hora]!;

      entry['cantidad'] = (entry['cantidad'] ?? 0) + 1;
      entry['total'] = (entry['total'] ?? 0) + _toDouble(s['total']);
    }

    return map;
  }

  Map<String, double> get _formasPago {
    final map = <String, double>{};

    for (final s in _activeSales) {
      final method = _metodoVenta(s);
      final total = _toDouble(s['total']);

      map[method] = (map[method] ?? 0) + total;
    }

    return map;
  }

  String _metodoVenta(Map<String, dynamic> sale) {
    final direct = sale['payment_method']?.toString().trim();

    if (direct != null && direct.isNotEmpty) return direct;

    return 'Efectivo';
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
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return '--/--/---- --:--';
    }

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

  String _formatearDiaMes(String fecha) {
    final partes = fecha.split('-');
    if (partes.length == 3) {
      return '${partes[2]}/${partes[1]}';
    }
    return fecha;
  }

  String _mesNombre(int mes) {
    const nombres = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];

    return mes >= 1 && mes <= 12 ? nombres[mes] : '';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : null,
          duration: const Duration(seconds: 3),
        ),
      );
  }

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
          _fechaFin = DateTime(
            picked.year,
            picked.month,
            picked.day,
            23,
            59,
            59,
          );
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
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,

      appBar: AppBar(
        title: Text(
          _companyName.isNotEmpty ? _companyName.toUpperCase() : 'ESTADÍSTICAS',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.today_outlined, size: 18), text: 'Día'),
            Tab(
              icon: Icon(Icons.calendar_month_outlined, size: 18),
              text: 'Mes',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDayTab(cs), _buildMonthTab(cs)],
      ),
    );
  }

  // ============================================================
  // TAB DÍA
  // ============================================================

  Widget _buildDayTab(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _buildDateRangeRow(),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                '${_formatDate(_fechaInicio)}  →  ${_formatDate(_fechaFin)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(child: _buildTotalCentral(cs)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildKpis(cs),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildVentasPorHora(cs),
            ),
          ),

          if (_formasPago.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _buildFormasPago(cs),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Top productos más vendidos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildTopProductos(_topProductos),
            ),
          ),

          if (_topPorDia.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Top productos por día',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _buildTopPorDia(_topPorDia),
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: 24)),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Ventas del rango',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),

          if (_sales.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: _buildEmptyState(
                  'Sin ventas',
                  'No existen ventas registradas en el rango seleccionado.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildSaleTile(_sales[i]),
                  ),
                  childCount: _sales.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // TAB MES
  // ============================================================

  Widget _buildMonthTab(ColorScheme cs) {
    if (_loadingMes) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Cargando estadísticas del mes...',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final hoy = DateTime.now();
    final mesNombre = _mesNombre(hoy.month);

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loadingMes = true);
        await _loadMonthStats();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: cs.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$mesNombre ${hoy.year}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Text(
                    'TOTAL DEL MES',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${_mesTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Ticket promedio',
                      value: '\$${_mesTicketPromedio.toStringAsFixed(2)}',
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.trending_up,
                      label: 'Transacciones',
                      value: '$_mesTransacciones',
                      color: cs.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_mesPorDia.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Ventas por día',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _buildMesPorDia(cs),
              ),
            ),
          ],

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Top productos más vendidos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildTopProductos(_mesTopProductos),
            ),
          ),

          if (_mesTopPorDia.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Top productos por día',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _buildTopPorDia(_mesTopPorDia),
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGETS
  // ============================================================

  Widget _buildDateRangeRow() {
    return Row(
      children: [
        Expanded(
          child: _DateButton(
            label: 'Fecha Inicio',
            date: _fechaInicio,
            onTap: () => _seleccionarFecha(esInicio: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DateButton(
            label: 'Fecha Fin',
            date: _fechaFin,
            onTap: () => _seleccionarFecha(esInicio: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalCentral(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            'TOTAL DEL PERIODO',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${_totalVentas.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: _InfoTile(
            icon: Icons.receipt_long_outlined,
            label: 'Tickets',
            value: '$_numeroTickets',
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.trending_up,
            label: 'Ticket promedio',
            value: '\$${_ticketPromedio.toStringAsFixed(2)}',
            color: cs.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            icon: Icons.account_balance,
            label: 'Impuestos',
            value: '\$${_totalImpuestos.toStringAsFixed(2)}',
            color: cs.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildVentasPorHora(ColorScheme cs) {
    final data = _ventasPorHora;

    double maxTotal = 0;
    for (final v in data.values) {
      final t = (v['total'] ?? 0);
      if (t > maxTotal) maxTotal = t;
    }

    if (maxTotal <= 0) {
      return _buildEmptyState(
        'Sin ventas por hora',
        'No existen ventas en el rango seleccionado.',
      );
    }

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ventas por hora',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (hora) {
                  final v = data[hora]!;
                  final total = v['total'] ?? 0;
                  final factor = maxTotal > 0 ? total / maxTotal : 0.0;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Tooltip(
                        message:
                            '$hora:00\n\$${total.toStringAsFixed(2)}\n'
                            '${(v['cantidad'] ?? 0).toInt()} venta(s)',
                        child: Container(
                          height: 6 + (60 * factor),
                          decoration: BoxDecoration(
                            color: total > 0
                                ? cs.primary
                                : cs.outlineVariant.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0h',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '6h',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '12h',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '18h',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                Text(
                  '23h',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormasPago(ColorScheme cs) {
    final entries = _formasPago.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Formas de pago',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Icon(_iconMetodo(e.key), size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '\$${e.value.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductos(List<Map<String, dynamic>> productos) {
    if (productos.isEmpty) {
      return _buildEmptyState(
        'Sin productos vendidos',
        'No existen ventas de productos en este periodo.',
      );
    }

    final maxVendido = productos
        .map((p) => _toDouble(p['total_vendido']))
        .fold(0.0, (a, b) => a > b ? a : b);

    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: productos.map((p) {
            final name = p['name']?.toString() ?? 'Producto';
            final vendido = _toDouble(p['total_vendido']);
            final monto = _toDouble(p['total_monto']);
            final factor = maxVendido > 0 ? vendido / maxVendido : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${vendido.toStringAsFixed(0)} u · '
                        '\$${monto.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: factor,
                      backgroundColor: cs.surface,
                      color: cs.primary,
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopPorDia(Map<String, List<Map<String, dynamic>>> data) {
    if (data.isEmpty) {
      return _buildEmptyState(
        'Sin datos por día',
        'No existen productos vendidos en el periodo.',
      );
    }

    final cs = Theme.of(context).colorScheme;

    final fechas = data.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fechas.map((fecha) {
        final productos = data[fecha] ?? const [];

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatearDiaMes(fecha),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (productos.isEmpty)
                    Text(
                      'Sin productos',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    ...productos.map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p['name']?.toString() ?? 'Producto',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_toDouble(p['total_vendido']).toStringAsFixed(0)} u',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '\$${_toDouble(p['total_monto']).toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMesPorDia(ColorScheme cs) {
    if (_mesPorDia.isEmpty) return const SizedBox.shrink();

    final maxTotal = _mesPorDia
        .map((x) => _toDouble(x['total']))
        .fold(0.0, (a, b) => a > b ? a : b);

    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: _mesPorDia.map((d) {
            final dia = d['dia']?.toString() ?? '';
            final total = _toDouble(d['total']);
            final cantidad = _toInt(d['cantidad']);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      dia,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxTotal > 0 ? total / maxTotal : 0,
                        backgroundColor: cs.surface,
                        color: cs.primary,
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '\$${total.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '$cantidad',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
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
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_iconMetodo(method), size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          method,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fechaHora,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ESTADO / ICONOS
  // ============================================================

  String _statusLabel(Map<String, dynamic> sale) {
    final raw = (sale['status'] ?? '').toString().trim().toLowerCase();

    if (raw == 'paid' || raw == 'pagado' || raw == 'pagada') return 'Pagada';
    if (raw == 'pending' || raw == 'pendiente') return 'Pendiente';
    if (raw == 'cancelled' ||
        raw == 'canceled' ||
        raw == 'cancelado' ||
        raw == 'cancelada' ||
        raw == 'anulado' ||
        raw == 'anulada') {
      return 'Cancelada';
    }

    return raw.isEmpty ? '—' : raw;
  }

  Color _statusColor(Map<String, dynamic> sale) {
    final raw = (sale['status'] ?? '').toString().trim().toLowerCase();

    if (raw == 'paid' || raw == 'pagado' || raw == 'pagada') {
      return const Color(0xFF4CAF50);
    }

    if (raw == 'pending' || raw == 'pendiente') {
      return Colors.orange;
    }

    if (raw == 'cancelled' ||
        raw == 'canceled' ||
        raw == 'cancelado' ||
        raw == 'cancelada' ||
        raw == 'anulado' ||
        raw == 'anulada') {
      return Colors.red;
    }

    return Colors.grey;
  }

  IconData _iconMetodo(String method) {
    final m = method.toLowerCase();

    if (m.contains('efectivo') || m == 'cash') {
      return Icons.payments_outlined;
    }

    if (m.contains('tarjeta') ||
        m.contains('card') ||
        m.contains('crédito') ||
        m.contains('débito')) {
      return Icons.credit_card_outlined;
    }

    if (m.contains('transfer')) {
      return Icons.swap_horiz;
    }

    if (m.contains('cheque') || m.contains('check')) {
      return Icons.receipt_outlined;
    }

    return Icons.attach_money;
  }
}

// ============================================================
// BOTÓN FECHA
// ============================================================

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

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
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$day/$month/$year',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// INFO TILE
// ============================================================

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

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
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
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
