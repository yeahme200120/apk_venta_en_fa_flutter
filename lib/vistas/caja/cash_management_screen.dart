import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/services/cash_service.dart';
import '../../core/storage/app_storage.dart';
import '../widgets/app_scaffold.dart';

class CashManagementScreen extends StatefulWidget {
  const CashManagementScreen({super.key});

  @override
  State<CashManagementScreen> createState() => _CashManagementScreenState();
}

class _CashManagementScreenState extends State<CashManagementScreen> {
  final CashService _service = CashService();
  final LocalDb _db = LocalDb();

  bool _loading = true;
  Map<String, dynamic>? _caja;
  Map<String, dynamic> _resumen = const {};
  Map<String, double> _porMetodo = const {};

  List<Map<String, dynamic>> _ventasPorMetodo = const [];
  List<Map<String, dynamic>> _movimientosPorTipoMetodo = const [];
  List<Map<String, dynamic>> _movimientos = const [];

  // ============================================================
  // FECHA COMERCIAL (AUTORIZADA POR EL SERVIDOR)
  // ============================================================
  //
  // La fecha comercial la manda el backend. NO usamos DateTime.now()
  // para el rango por defecto ni para comparaciones de caja.
  //
  String? _businessDateKey;

  DateTime _desde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _hasta = DateTime.now();

  String _tipoFiltro = 'todos';

  // ============================================================
  // TIEMPO REAL
  // ============================================================

  StreamSubscription<void>? _cashSub;
  StreamSubscription<void>? _operationSub;

  /// Si es `true`, el próximo evento de stream se ignora porque
  /// fue disparado por nosotros mismos.
  bool _suppressNextReload = false;

  bool get _cajaAbierta {
    final caja = _caja;
    if (caja == null) return false;
    return caja['estado']?.toString().toLowerCase() == 'abierta';
  }

  /// Fecha comercial como DateTime (medianoche).
  DateTime get _businessDate {
    final key = _businessDateKey;

    if (key != null && key.isNotEmpty) {
      final parsed = DateTime.tryParse(key);

      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }

    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();

    _cashSub = LocalDb.cashChanges.listen((_) {
      _onExternalCashChange();
    });

    _operationSub = LocalDb.operationChanges.listen((_) {
      _onExternalCashChange();
    });

    _initialize();
  }

  @override
  void dispose() {
    _cashSub?.cancel();
    _cashSub = null;

    _operationSub?.cancel();
    _operationSub = null;

    super.dispose();
  }

  /// Carga la fecha comercial del servidor y luego carga datos.
  Future<void> _initialize() async {
    final key = await AppStorage().getServerBusinessDateKey();

    if (!mounted) return;

    if (key != null && key.isNotEmpty) {
      final parsed = DateTime.tryParse(key);

      if (parsed != null) {
        final business = DateTime(parsed.year, parsed.month, parsed.day);

        setState(() {
          _businessDateKey = key;
          _hasta = business;
          _desde = business.subtract(const Duration(days: 7));
        });
      } else {
        setState(() => _businessDateKey = key);
      }
    }

    await _load();
  }

  void _onExternalCashChange() async {
    if (!mounted) return;

    // Si la fecha comercial cambió (por login, syncPull, cleanup, etc.)
    // recargamos la fecha y los datos.
    final key = await AppStorage().getServerBusinessDateKey();

    if (!mounted) return;

    if (key != null && key.isNotEmpty && key != _businessDateKey) {
      final parsed = DateTime.tryParse(key);

      if (parsed != null) {
        final business = DateTime(parsed.year, parsed.month, parsed.day);

        setState(() {
          _businessDateKey = key;
          _hasta = business;
          _desde = business.subtract(const Duration(days: 7));
        });
      } else {
        setState(() => _businessDateKey = key);
      }
    }

    if (_suppressNextReload) {
      _suppressNextReload = false;
      return;
    }

    _load(silent: true);
  }

  // ============================================================
  // CARGA
  // ============================================================

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final caja = await _db.getCurrentCashRegisterLocal();

      Map<String, dynamic> resumen = const {};
      Map<String, double> porMetodo = const {};
      List<Map<String, dynamic>> movimientos = const [];
      List<Map<String, dynamic>> ventasPorMetodo = const [];
      List<Map<String, dynamic>> movimientosPorTipoMetodo = const [];

      if (caja != null) {
        resumen = await _db.getCashSummaryLocal(
          cashRegisterId: caja['id'] as int,
        );

        final todos = await _db.getCashMovementsLocal(
          cashRegisterId: caja['id'] as int,
          tipo: _tipoFiltro == 'todos' ? null : _tipoFiltro,
          desde: DateTime(_desde.year, _desde.month, _desde.day),
          hasta: DateTime(_hasta.year, _hasta.month, _hasta.day, 23, 59, 59),
        );

        movimientos = todos
            .where((m) => m['tipo'] != 'apertura' && m['tipo'] != 'cierre')
            .toList();

        porMetodo = _calcularPorMetodo(movimientos);

        final fechaCaja = caja['fecha_comercial']?.toString() ?? '';

        if (fechaCaja.isNotEmpty) {
          // ⚠️ Usamos la fecha comercial de la CAJA (que ya viene
          // del servidor). NO DateTime.now().
          final fecha = DateTime.tryParse(fechaCaja) ?? _businessDate;

          ventasPorMetodo = await _db.getSalesByPaymentMethodLocal(
            businessDate: fecha,
          );
        }

        movimientosPorTipoMetodo = await _db.getMovementsByTypeAndMethodLocal(
          cashRegisterId: caja['id'] as int,
        );
      }

      if (!mounted) return;

      setState(() {
        _caja = caja;
        _resumen = resumen;
        _porMetodo = porMetodo;
        _movimientos = movimientos;
        _ventasPorMetodo = ventasPorMetodo;
        _movimientosPorTipoMetodo = movimientosPorTipoMetodo;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() => _loading = false);

      debugPrint('⚠️ Error cargando gestión de caja: $error');
    }
  }

  Map<String, double> _calcularPorMetodo(List<Map<String, dynamic>> movs) {
    final map = <String, double>{};

    for (final m in movs) {
      final tipo = (m['tipo'] ?? '').toString().toLowerCase();
      final monto = _d(m['monto']);
      final forma = (m['forma_pago'] ?? '').toString().trim();

      if (monto <= 0) continue;

      if (tipo != 'ingreso' &&
          tipo != 'egreso' &&
          tipo != 'retiro' &&
          tipo != 'ajuste') {
        continue;
      }

      final key = forma.isEmpty ? 'Sin especificar' : forma;

      if (tipo == 'ingreso' || tipo == 'ajuste') {
        map[key] = (map[key] ?? 0) + monto;
      } else {
        map[key] = (map[key] ?? 0) - monto;
      }
    }

    return map;
  }

  // ============================================================
  // ACCIONES
  // ============================================================

  Future<void> _abrirCaja() async {
    final monto = await showDialog<double>(
      context: context,
      builder: (_) => const _AmountDialog(
        titulo: 'Abrir caja',
        label: 'Monto de apertura',
      ),
    );

    if (monto == null) return;

    try {
      await _service.openCash(montoApertura: monto);

      _suppressNextReload = true;

      LocalDb.notifyCashChanged();
      LocalDb.notifyOperationChanged();

      if (!mounted) return;
      await _load(silent: true);

      _snack('Caja abierta correctamente.');
    } catch (e) {
      _snack('Error al abrir caja: $e', error: true);
    }
  }

  Future<void> _cerrarCaja() async {
    if (!_cajaAbierta) {
      _snack('No hay caja abierta para cerrar.', error: true);
      return;
    }

    final monto = await showDialog<double>(
      context: context,
      builder: (_) => const _AmountDialog(
        titulo: 'Cerrar caja',
        label: 'Efectivo declarado',
      ),
    );

    if (monto == null) return;

    try {
      await _service.closeCash(
        cashRegisterId: _caja!['id'] as int,
        montoDeclarado: monto,
      );

      _suppressNextReload = true;

      LocalDb.notifyCashChanged();
      LocalDb.notifyOperationChanged();

      if (!mounted) return;
      await _load(silent: true);

      _snack('Caja cerrada correctamente.');
    } catch (e) {
      _snack('Error al cerrar caja: $e', error: true);
    }
  }

  Future<void> _registrarMovimiento() async {
    if (!_cajaAbierta) {
      _snack('Abre la caja antes de registrar movimientos.', error: true);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _MovementDialog(),
    );

    if (result == null) return;

    try {
      await _service.addMovement(
        cashRegisterId: _caja!['id'] as int,
        tipo: result['tipo'] as String,
        concepto: result['concepto'] as String,
        monto: result['monto'] as double,
        referencia: result['referencia'] as String?,
        notas: result['notas'] as String?,
        formaPago: result['forma_pago'] as String?,
      );

      _suppressNextReload = true;
      LocalDb.notifyCashChanged();

      if (!mounted) return;
      await _load(silent: true);
    } catch (e) {
      _snack('Error al registrar movimiento: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const AppScaffold(
        title: 'Movimientos',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final fab = _cajaAbierta
        ? FloatingActionButton.extended(
            onPressed: _registrarMovimiento,
            icon: const Icon(Icons.add),
            label: const Text('Movimiento'),
          )
        : FloatingActionButton.extended(
            onPressed: _abrirCaja,
            icon: const Icon(Icons.lock_open),
            label: const Text('Abrir caja'),
          );

    return AppScaffold(
      title: 'Movimientos',
      floatingActionButton: fab,
      body: RefreshIndicator(
        onRefresh: () => _load(silent: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '💰 Gestión de Cajas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refrescar',
                  onPressed: () => _load(silent: false),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Administra aperturas, cierres y movimientos de caja.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _cajaAbierta ? _registrarMovimiento : _abrirCaja,
                icon: Icon(
                  _cajaAbierta ? Icons.add : Icons.lock_open,
                  size: 18,
                ),
                label: Text(
                  _cajaAbierta ? 'Registrar movimiento' : 'Abrir caja',
                ),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              ),
            ),

            const SizedBox(height: 16),

            _buildCajaActual(cs),

            if (_ventasPorMetodo.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDesgloseVentas(cs),
            ],

            if (_movimientosPorTipoMetodo.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDesgloseMovimientos(cs),
            ],

            const SizedBox(height: 12),
            _buildResumen(cs),

            if (_porMetodo.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildDesglosePorMetodo(cs),
            ],

            const SizedBox(height: 20),
            Text(
              'Historial de operaciones',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Consulta los movimientos registrados en las cajas.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _buildFiltros(),
            const SizedBox(height: 8),
            _buildTablaMovimientos(cs),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAJA ACTUAL
  // ============================================================

  Widget _buildCajaActual(ColorScheme cs) {
    final abierta = _cajaAbierta;

    final apertura = _d(_caja?['monto_apertura']);
    final declarado = _d(_caja?['monto_declarado']);
    final diferencia = _d(_caja?['diferencia']);

    final ingresos = _d(_resumen['ingresos']);
    final egresos = _d(_resumen['retiros_gastos']);
    final ajustes = _d(_resumen['ajustes']);
    final ventasEfectivo = _d(_resumen['ventas_efectivo']);

    final esperadoEnVivo = abierta
        ? (apertura + ventasEfectivo + ingresos + ajustes - egresos)
        : _d(_caja?['monto_esperado']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Caja actual',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  abierta ? Icons.lock_open : Icons.lock_outline,
                  color: abierta ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    abierta
                        ? 'Caja abierta'
                        : (_caja == null ? 'Sin caja abierta' : 'Caja cerrada'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (abierta)
                  FilledButton.tonal(
                    onPressed: _cerrarCaja,
                    child: const Text('Cerrar'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            _kv('Monto apertura', _m(apertura)),
            _kv(
              'Ventas en efectivo',
              _m(ventasEfectivo),
              color: Colors.green.shade700,
            ),
            _kv('Ingresos manuales', _m(ingresos)),
            _kv('Retiros / gastos', _m(egresos)),
            if (ajustes != 0) _kv('Ajustes', _m(ajustes)),
            const Divider(height: 16),
            _kv('Monto esperado', _m(esperadoEnVivo), bold: true),

            if (!abierta && _caja != null) ...[
              _kv('Monto declarado', _m(declarado)),
              _kv(
                'Diferencia',
                _m(diferencia),
                color: diferencia == 0
                    ? null
                    : (diferencia > 0
                          ? Colors.green.shade700
                          : Colors.red.shade700),
              ),
            ],

            _kv(
              'Fecha comercial',
              _caja?['fecha_comercial']?.toString() ?? '—',
            ),
            _kv('Apertura', _fmt(_caja?['abierta_at']?.toString())),
            if (_caja?['cerrada_at'] != null)
              _kv('Cierre', _fmt(_caja?['cerrada_at']?.toString())),

            if (!abierta) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.error.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Abre la caja con el botón "Abrir caja" para poder registrar movimientos.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DESGLOSE DE VENTAS
  // ============================================================

  Widget _buildDesgloseVentas(ColorScheme cs) {
    final total = _ventasPorMetodo.fold<double>(
      0,
      (acc, v) => acc + _d(v['total']),
    );
    final tickets = _ventasPorMetodo.fold<int>(
      0,
      (acc, v) => acc + _i(v['tickets']),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ventas del día por tipo de pago',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$tickets ticket(s) · ${_m(total)}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ..._ventasPorMetodo.map(
              (v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _iconMetodo(v['method_label']?.toString() ?? ''),
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v['method_label']?.toString() ?? '—',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_i(v['tickets'])} ticket(s)',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _m(v['total']),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total ventas',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _m(total),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DESGLOSE DE MOVIMIENTOS
  // ============================================================

  Widget _buildDesgloseMovimientos(ColorScheme cs) {
    final porTipo = <String, List<Map<String, dynamic>>>{};

    for (final m in _movimientosPorTipoMetodo) {
      final tipo = (m['tipo'] ?? '').toString();
      porTipo.putIfAbsent(tipo, () => []);
      porTipo[tipo]!.add(m);
    }

    const orden = ['ingreso', 'ajuste', 'egreso', 'retiro'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_vert, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Movimientos manuales por tipo y método',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...orden.where(porTipo.containsKey).map((tipo) {
              final items = porTipo[tipo]!;
              final totalTipo = items.fold<double>(
                0,
                (acc, v) => acc + _d(v['total']),
              );
              final color = _colorTipo(tipo);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildTipoBadge(tipo, cs),
                        const Spacer(),
                        Text(
                          _m(totalTipo),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...items.map(
                      (m) => Padding(
                        padding: const EdgeInsets.only(
                          left: 12,
                          top: 2,
                          bottom: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _iconMetodo(m['method_label']?.toString() ?? ''),
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m['method_label']?.toString() ?? '—',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              '${_i(m['cantidad'])}x  ',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _m(m['total']),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // RESUMEN
  // ============================================================

  Widget _buildResumen(ColorScheme cs) {
    final ingresos = _d(_resumen['ingresos']);
    final egresos = _d(_resumen['retiros_gastos']);
    final ajustes = _d(_resumen['ajustes']);
    final ventasEfectivo = _d(_resumen['ventas_efectivo']);
    final ventasTotal = _d(_resumen['ventas_total']);
    final movimientos = _i(_resumen['movimientos']);
    final neto = _d(_resumen['neto']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de movimientos',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 8),

            _kv(
              'Ventas en efectivo',
              _m(ventasEfectivo),
              color: Colors.green.shade700,
            ),
            if (ventasTotal > ventasEfectivo)
              _kv(
                'Ventas otros métodos',
                _m(ventasTotal - ventasEfectivo),
                color: Colors.grey.shade700,
              ),

            const Divider(height: 16),

            _kv(
              'Ingresos manuales',
              _m(ingresos),
              color: Colors.green.shade700,
            ),
            _kv('Retiros / gastos', _m(egresos), color: Colors.red.shade700),
            if (ajustes != 0)
              _kv('Ajustes', _m(ajustes), color: Colors.blue.shade700),

            const Divider(height: 16),

            _kv('Movimientos registrados', movimientos.toString()),
            _kv(
              'Neto en caja',
              _m(neto),
              bold: true,
              color: neto >= 0 ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TOTALES NETOS POR MÉTODO
  // ============================================================

  Widget _buildDesglosePorMetodo(ColorScheme cs) {
    final entries = _porMetodo.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Totales por método de pago (manuales)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...entries.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _iconMetodo(e.key),
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
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
                      _m(e.value),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: e.value >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _m(_porMetodo.values.fold<double>(0, (a, b) => a + b)),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // FILTROS
  // ============================================================

  Widget _buildFiltros() {
    // ⚠️ El picker permite hasta la fecha comercial del servidor.
    // Nunca fechas futuras más allá del día operativo.
    final lastDate = _businessDate.add(const Duration(days: 1));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: _desde,
              firstDate: DateTime(2020),
              lastDate: lastDate,
            );
            if (p != null && mounted) {
              setState(() => _desde = p);
              _load(silent: true);
            }
          },
          icon: const Icon(Icons.calendar_today, size: 16),
          label: Text(
            '${_desde.day.toString().padLeft(2, '0')}/'
            '${_desde.month.toString().padLeft(2, '0')}/'
            '${_desde.year}',
          ),
        ),
        DropdownButton<String>(
          value: _tipoFiltro,
          items: const [
            DropdownMenuItem(value: 'todos', child: Text('Todos los tipos')),
            DropdownMenuItem(value: 'ingreso', child: Text('Ingresos')),
            DropdownMenuItem(value: 'egreso', child: Text('Egresos')),
            DropdownMenuItem(value: 'retiro', child: Text('Retiros')),
            DropdownMenuItem(value: 'ajuste', child: Text('Ajustes')),
          ],
          onChanged: (v) {
            setState(() => _tipoFiltro = v ?? 'todos');
            _load(silent: true);
          },
        ),
      ],
    );
  }

  // ============================================================
  // TABLA DE MOVIMIENTOS
  // ============================================================

  Widget _buildTablaMovimientos(ColorScheme cs) {
    if (_movimientos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              const Text(
                'No hay operaciones',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'No existen movimientos para los filtros seleccionados.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: cs.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: const [
                  Expanded(flex: 3, child: Text('Fecha', style: _h)),
                  Expanded(flex: 2, child: Text('Tipo', style: _h)),
                  Expanded(flex: 4, child: Text('Concepto', style: _h)),
                  Expanded(flex: 3, child: Text('Método', style: _h)),
                  Expanded(flex: 2, child: Text('Monto', style: _h)),
                ],
              ),
            ),
          ),
          ..._movimientos.map(
            (m) => Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      _fmt(m['registrado_at']?.toString()),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _buildTipoBadge((m['tipo'] ?? '').toString(), cs),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      (m['concepto'] ?? '').toString(),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      (m['forma_pago'] ?? '—').toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _m(m['monto']),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _esEntrada(m['tipo'])
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AUXILIARES
  // ============================================================

  Widget _buildTipoBadge(String tipo, ColorScheme cs) {
    final color = _colorTipo(tipo);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _labelTipo(tipo),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  String _labelTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'ingreso':
        return 'Ingreso';
      case 'egreso':
        return 'Egreso';
      case 'retiro':
        return 'Retiro';
      case 'ajuste':
        return 'Ajuste';
      case 'apertura':
        return 'Apertura';
      case 'cierre':
        return 'Cierre';
      default:
        return tipo;
    }
  }

  Color _colorTipo(String tipo) {
    switch (tipo.toLowerCase()) {
      case 'ingreso':
        return Colors.green.shade700;
      case 'egreso':
        return Colors.red.shade700;
      case 'retiro':
        return Colors.orange.shade700;
      case 'ajuste':
        return Colors.blue.shade700;
      case 'apertura':
      case 'cierre':
        return Colors.grey.shade700;
      default:
        return Colors.grey;
    }
  }

  bool _esEntrada(dynamic tipo) {
    final t = (tipo ?? '').toString().toLowerCase();
    return t == 'ingreso' || t == 'apertura' || t == 'ajuste';
  }

  IconData _iconMetodo(String metodo) {
    final m = metodo.toLowerCase();

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

  static const _h = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);

  Widget _kv(String k, String v, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _m(dynamic v) => '\$${_d(v).toStringAsFixed(2)}';

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}

// ============================================================
// DIÁLOGO DE MONTO
// ============================================================

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.titulo, required this.label});

  final String titulo;
  final String label;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _ctrl = TextEditingController(text: '0.00');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(_ctrl.text.replaceAll(',', '.')),
          ),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

// ============================================================
// DIÁLOGO DE MOVIMIENTO
// ============================================================

class _MovementDialog extends StatefulWidget {
  const _MovementDialog();

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _concepto = TextEditingController();
  final _monto = TextEditingController();
  final _referencia = TextEditingController();
  final _notas = TextEditingController();

  String _tipo = 'ingreso';
  String? _formaPago;

  @override
  void dispose() {
    _concepto.dispose();
    _monto.dispose();
    _referencia.dispose();
    _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar movimiento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'ingreso', child: Text('Ingreso')),
                DropdownMenuItem(value: 'egreso', child: Text('Egreso')),
                DropdownMenuItem(value: 'retiro', child: Text('Retiro')),
                DropdownMenuItem(value: 'ajuste', child: Text('Ajuste')),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? 'ingreso'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _concepto,
              decoration: const InputDecoration(labelText: 'Concepto *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto *',
                prefixText: '\$',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _referencia,
              decoration: const InputDecoration(labelText: 'Referencia'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _formaPago,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Sin especificar')),
                DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                DropdownMenuItem(value: 'Tarjeta', child: Text('Tarjeta')),
                DropdownMenuItem(
                  value: 'Transferencia',
                  child: Text('Transferencia'),
                ),
              ],
              onChanged: (v) => setState(() => _formaPago = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notas,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final concepto = _concepto.text.trim();
            final monto = double.tryParse(_monto.text.replaceAll(',', '.'));

            if (concepto.isEmpty || monto == null || monto <= 0) {
              return;
            }

            Navigator.pop(context, {
              'tipo': _tipo,
              'concepto': concepto,
              'monto': monto,
              'referencia': _referencia.text.trim().isEmpty
                  ? null
                  : _referencia.text.trim(),
              'notas': _notas.text.trim().isEmpty ? null : _notas.text.trim(),
              'forma_pago': _formaPago,
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}