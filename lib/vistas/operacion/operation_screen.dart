import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/network/api_client.dart';
import '../../core/services/cash_service.dart';

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
  bool _canOperateCash = false;
  bool _tablesEnabled = false;

  /// Caja abierta en local (SQLite). Es la fuente de verdad offline-first.
  Map<String, dynamic>? _cashRegister;

  /// Estado devuelto por el backend (para permisos, mesas, etc).
  Map<String, dynamic>? _remoteCashRegister;

  List<Map<String, dynamic>> _tables = const [];
  Map<int, int> _pendingByTable = const {};

  // ============================================================
  // TIEMPO REAL
  // ============================================================

  StreamSubscription<void>? _cashSub;
  StreamSubscription<void>? _operationSub;

  /// Evita que un stream dispare una recarga mientras ya hay una
  /// recarga en curso.
  bool _isReloading = false;

  @override
  void initState() {
    super.initState();

    _cashSub = LocalDb.cashChanges.listen((_) => _reloadFromStream());
    _operationSub = LocalDb.operationChanges.listen((_) => _reloadFromStream());

    _load();
  }

  @override
  void dispose() {
    _cashSub?.cancel();
    _cashSub = null;

    _operationSub?.cancel();
    _operationSub = null;

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

      Map<String, dynamic>? remoteCash;
      Map<String, dynamic> state = const {};
      List<Map<String, dynamic>> tables = const [];

      try {
        state = await _api.getOperationStatus();
        remoteCash = await _api.getCurrentCashRegister();

        final tablesEnabled = state['mesas_activas'] == true;
        tables = tablesEnabled
            ? await _api.getTables()
            : const <Map<String, dynamic>>[];
      } catch (_) {
        // Offline: usamos solo lo local.
      }

      final tablesEnabled = state['mesas_activas'] == true;

      final pendingByTable = <int, int>{};

      for (final sale in await _localDb.getTodaySales()) {
        if (sale['status'] != 'pending' || sale['mesa_id'] is! num) continue;
        final tableId = (sale['mesa_id'] as num).toInt();
        pendingByTable[tableId] = (pendingByTable[tableId] ?? 0) + 1;
      }

      if (!mounted) return;

      setState(() {
        _cashRegister = localCash;
        _remoteCashRegister = remoteCash;
        _canOperateCash = state['puede_operar_caja'] == true;
        _tablesEnabled = tablesEnabled;
        _tables = tables;
        _pendingByTable = pendingByTable;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _isReloading = false;
    }
  }

  // ============================================================
  // ABRIR / REABRIR CAJA
  // ============================================================

  Future<void> _openCashDialog() async {
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
    final esperado = _d(caja?['monto_esperado']);
    final declarado = _d(caja?['monto_declarado']);
    final diferencia = _d(caja?['diferencia']);

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
                if (_canOperateCash)
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
              _kv('Monto esperado', '\$${esperado.toStringAsFixed(2)}', cs: cs),
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

  Widget _kv(String k, String v, {Color? color, required ColorScheme cs}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Text(
            v,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
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