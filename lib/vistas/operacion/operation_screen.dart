import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/network/api_client.dart';
import '../../core/services/cash_service.dart';
// [LICENCIA-OFFLINE] Import para evaluar el estado de licencia desde
// el snapshot local (offline-first).
import '../../core/services/license_service.dart';

class OperationScreen extends StatefulWidget {
  const OperationScreen({super.key});

  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends State<OperationScreen> {
  final ApiClient _api = ApiClient();
  final LocalDb _localDb = LocalDb();
  final CashService _cash = CashService();

  bool _loading = true;
  bool _cajasActivas = false;
  bool _tablesEnabled = false;

  Map<String, dynamic>? _cashRegister;
  Map<String, dynamic> _cashSummary = const {};

  List<Map<String, dynamic>> _tables = const [];
  Map<int, int> _pendingByTable = const {};

  // [LICENCIA-OFFLINE] Estado de licencia leído desde el snapshot local.
  // Nunca se consulta al servidor desde aquí.
  LicenseState? _licenseState;

  // ============================================================
  // TIEMPO REAL
  // ============================================================

  StreamSubscription<void>? _cashSub;
  StreamSubscription<void>? _operationSub;
  StreamSubscription<void>? _salesSub;

  bool _isReloading = false;

  @override
  void initState() {
    super.initState();

    _cashSub = LocalDb.cashChanges.listen((_) => _reloadFromStream());
    _operationSub = LocalDb.operationChanges.listen((_) => _reloadFromStream());
    _salesSub = LocalDb.salesChanges.listen((_) => _reloadFromStream());

    _load();
  }

  @override
  void dispose() {
    _cashSub?.cancel();
    _cashSub = null;

    _operationSub?.cancel();
    _operationSub = null;

    _salesSub?.cancel();
    _salesSub = null;

    super.dispose();
  }

  void _reloadFromStream() {
    if (!mounted) return;
    if (_isReloading) return;

    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (_isReloading) return;

    _isReloading = true;

    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final localCash = await _cash.getCurrentCash();

      Map<String, dynamic> summary = const {};

      if (localCash != null && localCash['id'] is num) {
        try {
          summary = await _cash.getSummary(localCash['id'] as int);
        } catch (_) {
          summary = const {};
        }
      }

      Map<String, dynamic> state = const {};
      List<Map<String, dynamic>> tables = const [];

      // ============================================================
      // LLAMADAS DE RED CON TIMEOUT
      // ============================================================
      //
      // Cada llamada de red tiene un timeout para que _load() nunca
      // se quede colgado. Si algo falla o tarda, seguimos con lo que
      // tengamos. El spinner siempre desaparece.
      try {
        state = await _api.getOperationStatus().timeout(
          const Duration(seconds: 10),
          onTimeout: () => const <String, dynamic>{},
        );

        await _api.getCurrentCashRegister().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );

        final tablesEnabled = state['mesas_activas'] == true;
        tables = tablesEnabled
            ? await _api.getTables().timeout(
                const Duration(seconds: 10),
                onTimeout: () => const <Map<String, dynamic>>[],
              )
            : const <Map<String, dynamic>>[];
      } catch (_) {
        // Offline o timeout. Seguimos con lo que tengamos.
      }

      final tablesEnabled = state['mesas_activas'] == true;

      final pendingByTable = <int, int>{};

      try {
        for (final sale in await _localDb.getTodaySales()) {
          if (sale['status'] != 'pending' || sale['mesa_id'] is! num) continue;
          final tableId = (sale['mesa_id'] as num).toInt();
          pendingByTable[tableId] = (pendingByTable[tableId] ?? 0) + 1;
        }
      } catch (_) {}

      if (!mounted) return;

      // [LICENCIA-OFFLINE] Evaluamos la licencia desde el snapshot local.
      // No se consulta al servidor. El POS sigue funcionando offline.
      LicenseState? licencia;
      try {
        licencia = await LicenseService().evaluate().timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              _licenseState ??
              const LicenseState(
                status: LicenseStatus.sinSnapshot,
                tipo: '',
                fechaFin: null,
                diasRestantes: null,
                diasVencidos: 0,
                mensaje: 'Sin información de licencia.',
              ),
        );
      } catch (e) {
        debugPrint('⚠️ No se pudo evaluar la licencia local: $e');
        licencia = _licenseState;
      }

      if (!mounted) return;

      setState(() {
        _cashRegister = localCash;
        _cashSummary = summary;
        _cajasActivas = state['cajas_activas'] == true;
        _tablesEnabled = tablesEnabled;
        _tables = tables;
        _pendingByTable = pendingByTable;
        _licenseState = licencia;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('⚠️ Error en OperationScreen._load: $error');

      // 🔑 Garantizar que el spinner desaparezca aunque algo falle.
      setState(() => _loading = false);
    } finally {
      _isReloading = false;
    }
  }

  // ============================================================
  // ABRIR / REABRIR CAJA
  // ============================================================

  Future<void> _openCashDialog() async {
    // [LICENCIA-OFFLINE] Abrir caja es una operación NUEVA.
    // Se bloquea si la licencia está explícitamente vencida
    // (status == LicenseStatus.bloqueada).
    //
    // NO bloquea sinSnapshot ni enGracia.
    if (_licenseState?.status == LicenseStatus.bloqueada) {
      _snack(_licenseState!.mensaje, error: true);
      return;
    }

    final amount = await _amountDialog(
      title: 'Abrir caja',
      label: 'Monto de apertura',
    );

    if (amount == null) return;

    try {
      final result = await _cash.openCash(montoApertura: amount);

      await _load(silent: true);

      final reapertura = result['reapertura'] == true;

      _snack(
        reapertura
            ? 'Caja reabierta. Ya había sido cerrada hoy.'
            : 'Caja abierta correctamente.',
      );
    } catch (error) {
      _snack('Error al abrir caja: $error', error: true);
    }
  }

  Future<void> _closeCashDialog() async {
    // [LICENCIA-OFFLINE] Cerrar caja SIEMPRE se permite, incluso si la
    // licencia está vencida. Si bloqueáramos el cierre, el usuario
    // quedaría con datos huérfanos (efectivo sin cuadrar, turno sin cerrar).
    //
    // No hay check de licencia aquí a propósito.

    final cashRegister = _cashRegister;
    if (cashRegister == null) return;

    final amount = await _amountDialog(
      title: 'Cerrar caja',
      label: 'Efectivo declarado',
    );

    if (amount == null) return;

    try {
      await _cash.closeCash(
        cashRegisterId: cashRegister['id'] as int,
        montoDeclarado: amount,
      );
      await _load(silent: true);
      _snack('Caja cerrada correctamente.');
    } catch (error) {
      _snack('Error al cerrar caja: $error', error: true);
    }
  }

  // ============================================================
  // RETIRO PARCIAL
  // ============================================================

  Future<void> _retiroParcialDialog() async {
    // [LICENCIA-OFFLINE] Retiro parcial SIEMPRE se permite.
    // Es una operación sobre una caja YA ABIERTA. Bloquearla dejaría
    // efectivo sin poder retirarse del turno.

    final cashRegister = _cashRegister;
    if (cashRegister == null) {
      _snack('No hay caja abierta.', error: true);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _RetiroParcialDialog(),
    );

    if (result == null) return;

    try {
      await _cash.addMovement(
        cashRegisterId: cashRegister['id'] as int,
        tipo: 'retiro',
        concepto: result['concepto'] as String,
        monto: result['monto'] as double,
        referencia: result['referencia'] as String?,
        notas: result['notas'] as String?,
        formaPago: 'Efectivo',
      );

      await _load(silent: true);

      _snack(
        'Retiro de \$${(result['monto'] as double).toStringAsFixed(2)} '
        'registrado correctamente.',
      );
    } catch (error) {
      _snack('Error al registrar retiro: $error', error: true);
    }
  }

  Future<double?> _amountDialog({
    required String title,
    required String label,
  }) async {
    return showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(title: title, label: label),
    );
  }

  // ============================================================
  // MESAS
  // ============================================================

  Future<void> _editTable([Map<String, dynamic>? table]) async {
    // [LICENCIA-OFFLINE] Editar mesas SIEMPRE se permite.
    // No es una operación que consuma licencia; es configuración.

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TableEditorDialog(table: table),
    );

    if (result == null || result['name'].toString().trim().isEmpty) return;

    try {
      await _api.saveTable(
        id: table?['id'] as int?,
        name: result['name'].toString(),
        capacity: result['capacity'] as int?,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
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
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: cs.surface,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // [LICENCIA-OFFLINE] Banners de licencia.
            // Orden de prioridad:
            //   1. bloqueada   → SÍ bloquea nuevas aperturas.
            //   2. sinSnapshot → NO bloquea, solo avisa.
            //   3. enGracia    → NO bloquea, solo avisa.
            if (_licenseState?.status == LicenseStatus.bloqueada) ...[
              _buildLicenciaBloqueadaBanner(context),
              const SizedBox(height: 12),
            ] else if (_licenseState?.status == LicenseStatus.sinSnapshot) ...[
              _buildLicenciaSinSnapshotBanner(context),
              const SizedBox(height: 12),
            ] else if (_licenseState?.debeAvisarGracia == true) ...[
              _buildLicenciaGraciaBanner(context),
              const SizedBox(height: 12),
            ],
            _buildCashCard(cs),
            if (_tablesEnabled) ...[
              const SizedBox(height: 20),
              _buildTablesHeader(),
              if (_tables.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No hay mesas configuradas.'),
                ),
              ..._tables.map(_buildTableCard),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CARD DE CAJA
  // ============================================================

  Widget _buildCashCard(ColorScheme cs) {
    final caja = _cashRegister;
    final abierta = caja != null;

    final apertura = _d(caja?['monto_apertura']);
    final declarado = _d(caja?['monto_declarado']);
    final diferencia = _d(caja?['diferencia']);

    final ventasEfectivo = _d(_cashSummary['ventas_efectivo']);
    final ingresos = _d(_cashSummary['ingresos']);
    final egresos = _d(_cashSummary['retiros_gastos']);
    final ajustes = _d(_cashSummary['ajustes']);

    // Retiros parciales del día (solo tipo "retiro").
    final retirosParciales = _d(_cashSummary['retiros_parciales']);
    final egresosOperativos = _d(_cashSummary['egresos_operativos']);

    // Monto esperado en vivo.
    final esperadoEnVivo = abierta
        ? (apertura + ventasEfectivo + ingresos + ajustes - egresos)
        : _d(caja?['monto_esperado']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  abierta ? Icons.lock_open : Icons.lock_outline,
                  color: abierta ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abierta ? 'Caja abierta' : 'Caja cerrada',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        abierta
                            ? 'Apertura: \$${apertura.toStringAsFixed(2)}'
                            : 'No hay caja abierta para hoy.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_cajasActivas)
                  FilledButton(
                    onPressed: abierta ? _closeCashDialog : _openCashDialog,
                    child: Text(abierta ? 'Cerrar' : 'Abrir'),
                  )
                else
                  Text(
                    'Solo cajero',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),

            if (abierta) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              _kv(
                'Ventas en efectivo',
                '\$${ventasEfectivo.toStringAsFixed(2)}',
                cs: cs,
                color: Colors.green.shade700,
              ),
              _kv(
                'Ingresos manuales',
                '\$${ingresos.toStringAsFixed(2)}',
                cs: cs,
              ),
              if (egresosOperativos != 0)
                _kv(
                  'Egresos operativos',
                  '\$${egresosOperativos.toStringAsFixed(2)}',
                  cs: cs,
                  color: Colors.red.shade700,
                ),
              if (ajustes != 0)
                _kv(
                  'Ajustes',
                  '\$${ajustes.toStringAsFixed(2)}',
                  cs: cs,
                  color: Colors.blue.shade700,
                ),

              // ============================================================
              // RETIROS PARCIALES DEL DÍA
              // ============================================================
              //
              // Se muestra siempre (aunque sea $0.00) para que el cajero
              // vea que existe la opción de retirar efectivo parcial.
              //
              _kv(
                'Retiros parciales del día',
                '\$${retirosParciales.toStringAsFixed(2)}',
                cs: cs,
                color: retirosParciales > 0
                    ? Colors.orange.shade800
                    : cs.onSurfaceVariant,
                bold: retirosParciales > 0,
              ),

              const Divider(height: 16),

              _kv(
                'Monto esperado',
                '\$${esperadoEnVivo.toStringAsFixed(2)}',
                cs: cs,
                bold: true,
              ),
              _kv(
                'Monto declarado',
                '\$${declarado.toStringAsFixed(2)}',
                cs: cs,
              ),
              _kv(
                'Diferencia',
                '\$${diferencia.toStringAsFixed(2)}',
                color: diferencia == 0
                    ? null
                    : (diferencia > 0
                          ? Colors.green.shade700
                          : Colors.red.shade700),
                cs: cs,
              ),

              // ============================================================
              // ACCIONES DE CAJA
              // ============================================================
              //
              // El retiro parcial solo se habilita cuando la caja está
              // abierta y el usuario puede operarla.
              //
              if (_cajasActivas) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _retiroParcialDialog,
                    icon: const Icon(Icons.savings_outlined, size: 18),
                    label: const Text('Registrar retiro parcial'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(color: Colors.orange.shade300),
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Gestiona los movimientos desde la pestaña "Caja" → "Movimientos"',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // [LICENCIA-OFFLINE] BANNERS DE LICENCIA
  // ============================================================
  //
  // Mismos 3 banners que el POS. Coherencia visual y lógica.
  //
  //   1. bloqueada    → rojo, SÍ bloquea nuevas aperturas de caja.
  //   2. sinSnapshot  → ámbar, NO bloquea (offline-first).
  //   3. enGracia     → naranja, NO bloquea.
  // ============================================================

  Widget _buildLicenciaBloqueadaBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mensaje =
        _licenseState?.mensaje ??
        'Tu licencia está vencida. Inicia sesión con Internet para '
            'reactivar.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.error.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error.withAlpha(90), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.error.withAlpha(30),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.block, color: colorScheme.error, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Licencia vencida',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$mensaje\n'
                  'Puedes cerrar la caja, registrar movimientos y '
                  'sincronizar pendientes.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenciaSinSnapshotBanner(BuildContext context) {
    const amber = Color(0xFFB45309);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: amber.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withAlpha(90), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: amber.withAlpha(30),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: amber,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sin información de licencia',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Conéctate a Internet e inicia sesión para validar tu '
                  'licencia. Mientras tanto puedes seguir operando.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenciaGraciaBanner(BuildContext context) {
    final orange = Colors.orange.shade800;
    final colorScheme = Theme.of(context).colorScheme;

    final mensaje =
        _licenseState?.mensaje ??
        'Tu licencia está vencida. Regulariza antes de que se bloquee.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: orange.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orange.withAlpha(90), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: orange.withAlpha(30),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.warning_amber_rounded, color: orange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Licencia en periodo de gracia',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mensaje,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MESAS
  // ============================================================

  Widget _buildTablesHeader() {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Mesas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
        ),
        IconButton(
          onPressed: () => _editTable(),
          icon: Icon(Icons.add, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table) {
    final tableId = (table['id'] as num).toInt();
    final pendientes = _pendingByTable[tableId];
    final ocupada = table['estado'] == 'ocupada' || pendientes != null;

    final subtitulo = StringBuffer();

    subtitulo.write(table['estado'] ?? 'libre');

    if (table['capacidad'] != null) {
      subtitulo.write(' · ${table['capacidad']} personas');
    }

    if (pendientes != null) {
      subtitulo.write(' · $pendientes venta(s) pendiente(s) local(es)');
    }

    return Card(
      child: ListTile(
        leading: Icon(
          ocupada ? Icons.table_restaurant : Icons.table_bar_outlined,
        ),
        title: Text(table['nombre'].toString()),
        subtitle: Text(subtitulo.toString()),
        trailing: IconButton(
          onPressed: () => _editTable(table),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

  Widget _kv(
    String k,
    String v, {
    Color? color,
    bool bold = false,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}

// ============================================================
// DIÁLOGO MONTO
// ============================================================

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _controller = TextEditingController(text: '0.00');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
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
          double.tryParse(_controller.text.replaceAll(',', '.')),
        ),
        child: const Text('Confirmar'),
      ),
    ],
  );
}

// ============================================================
// DIÁLOGO RETIRO PARCIAL
// ============================================================

class _RetiroParcialDialog extends StatefulWidget {
  const _RetiroParcialDialog();

  @override
  State<_RetiroParcialDialog> createState() => _RetiroParcialDialogState();
}

class _RetiroParcialDialogState extends State<_RetiroParcialDialog> {
  final _concepto = TextEditingController(text: 'Retiro parcial de caja');
  final _monto = TextEditingController();
  final _referencia = TextEditingController();
  final _notas = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _concepto.dispose();
    _monto.dispose();
    _referencia.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _confirmar() {
    final concepto = _concepto.text.trim();
    final monto = double.tryParse(_monto.text.replaceAll(',', '.'));

    if (concepto.isEmpty) {
      setState(() => _error = 'Ingresa un concepto.');
      return;
    }

    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresa un monto válido mayor a cero.');
      return;
    }

    Navigator.pop(context, {
      'concepto': concepto,
      'monto': monto,
      'referencia': _referencia.text.trim().isEmpty
          ? null
          : _referencia.text.trim(),
      'notas': _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.savings_outlined, size: 22),
          SizedBox(width: 8),
          Text('Retiro parcial'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Retira efectivo de la caja sin cerrarla. '
              'El monto se descuenta del esperado.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _concepto,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Concepto *',
                hintText: 'Retiro parcial de caja',
                prefixIcon: Icon(Icons.description_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _monto,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto *',
                hintText: '0.00',
                prefixText: '\$ ',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _referencia,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _notas,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                prefixIcon: Icon(Icons.notes_outlined),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _confirmar,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Registrar retiro'),
        ),
      ],
    );
  }
}

// ============================================================
// DIÁLOGO MESA
// ============================================================

class _TableEditorDialog extends StatefulWidget {
  const _TableEditorDialog({this.table});

  final Map<String, dynamic>? table;

  @override
  State<_TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<_TableEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.table?['nombre']?.toString() ?? '',
    );
    _capacity = TextEditingController(
      text: widget.table?['capacidad']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.table == null ? 'Nueva mesa' : 'Editar mesa'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        TextField(
          controller: _capacity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Capacidad'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'name': _name.text,
          'capacity': int.tryParse(_capacity.text),
        }),
        child: const Text('Guardar'),
      ),
    ],
  );
}