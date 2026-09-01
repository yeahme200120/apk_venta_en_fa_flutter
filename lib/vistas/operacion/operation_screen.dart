import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/database/local_db.dart';

class OperationScreen extends StatefulWidget {
  const OperationScreen({super.key});

  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends State<OperationScreen> {
  final ApiClient _api = ApiClient();
  final LocalDb _localDb = LocalDb();
  bool _loading = true;
  bool _canOperateCash = false;
  bool _tablesEnabled = false;
  Map<String, dynamic>? _cashRegister;
  List<Map<String, dynamic>> _tables = const [];
  Map<int, int> _pendingByTable = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _api.getOperationStatus();
      final tablesEnabled = state['mesas_activas'] == true;
      final cashRegister = await _api.getCurrentCashRegister();
      final tables = tablesEnabled ? await _api.getTables() : const <Map<String, dynamic>>[];
      final pendingByTable = <int, int>{};
      for (final sale in await _localDb.getTodaySales()) {
        if (sale['status'] != 'pending' || sale['mesa_id'] is! num) continue;
        final tableId = (sale['mesa_id'] as num).toInt();
        pendingByTable[tableId] = (pendingByTable[tableId] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _canOperateCash = state['puede_operar_caja'] == true;
        _tablesEnabled = tablesEnabled;
        _cashRegister = cashRegister;
        _tables = tables;
        _pendingByTable = pendingByTable;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCashDialog() async {
    final amount = await _amountDialog(title: 'Abrir caja', label: 'Monto de apertura');
    if (amount == null) return;
    try {
      await _api.openCashRegister(openingAmount: amount);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _closeCashDialog() async {
    final cashRegister = _cashRegister;
    if (cashRegister == null) return;
    final amount = await _amountDialog(title: 'Cerrar caja', label: 'Efectivo declarado');
    if (amount == null) return;
    try {
      await _api.closeCashRegister(cashRegisterId: (cashRegister['id'] as num).toInt(), declaredAmount: amount);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<double?> _amountDialog({required String title, required String label}) async {
    return showDialog<double>(
      context: context,
      builder: (_) => _AmountDialog(title: title, label: label),
    );
  }

  Future<void> _editTable([Map<String, dynamic>? table]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TableEditorDialog(table: table),
    );
    if (result == null || result['name'].toString().trim().isEmpty) return;
    try {
      await _api.saveTable(id: table?['id'] as int?, name: result['name'].toString(), capacity: result['capacity'] as int?);
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operación')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Card(child: ListTile(
                  leading: Icon(_cashRegister == null ? Icons.lock_outline : Icons.lock_open_outlined),
                  title: Text(_cashRegister == null ? 'Caja cerrada' : 'Caja abierta'),
                  subtitle: Text(
                    _cashRegister == null
                        ? 'No hay caja abierta para hoy.'
                        : 'Apertura: \$${_cashRegister!['monto_apertura']}',
                  ),
                  trailing: _canOperateCash
                      ? FilledButton(
                          onPressed: _cashRegister == null ? _openCashDialog : _closeCashDialog,
                          child: Text(_cashRegister == null ? 'Abrir' : 'Cerrar'),
                        )
                      : const Text('Solo cajero'),
                )),
                if (_tablesEnabled) ...[
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(child: Text('Mesas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => _editTable(), icon: const Icon(Icons.add)),
                  ]),
                  if (_tables.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('No hay mesas configuradas.')),
                  ..._tables.map((table) => Card(child: ListTile(
                    leading: Icon(table['estado'] == 'ocupada' || _pendingByTable[(table['id'] as num).toInt()] != null ? Icons.table_restaurant : Icons.table_bar_outlined),
                    title: Text(table['nombre'].toString()),
                    subtitle: Text('${table['estado'] ?? 'libre'}${table['capacidad'] == null ? '' : ' · ${table['capacidad']} personas'}${_pendingByTable[(table['id'] as num).toInt()] == null ? '' : ' · ${_pendingByTable[(table['id'] as num).toInt()]} venta(s) pendiente(s) local(es)'}'),
                    trailing: IconButton(onPressed: () => _editTable(table), icon: const Icon(Icons.edit_outlined)),
                  ))),
                ],
              ]),
            ),
    );
  }
}

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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(_controller.text.replaceAll(',', '.'))), child: const Text('Confirmar')),
        ],
      );
}

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
    _name = TextEditingController(text: widget.table?['nombre']?.toString() ?? '');
    _capacity = TextEditingController(text: widget.table?['capacidad']?.toString() ?? '');
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: _capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacidad')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, {'name': _name.text, 'capacity': int.tryParse(_capacity.text)}), child: const Text('Guardar')),
        ],
      );
}
