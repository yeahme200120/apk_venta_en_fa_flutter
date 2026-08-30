import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/services/printer_service.dart';
import '../../core/services/permission_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrinterService _service = PrinterService();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  List<BluetoothInfo> _printers = [];
  String? _connectedAddress;
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() { _loading = true; _message = null; });
    try {
      if (!await PermissionService().requestBluetoothPermissions()) {
        throw Exception('Se requieren permisos Bluetooth para buscar impresoras nuevas.');
      }
      _printers = await _service.pairedBluetoothPrinters();
    } catch (error) {
      _message = 'No se pudieron consultar impresoras Bluetooth: $error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _connect(BluetoothInfo printer) async {
    setState(() { _loading = true; _message = null; });
    try {
      final connected = await _service.connectBluetooth(printer.macAdress);
      _connectedAddress = connected ? printer.macAdress : null;
      _message = connected ? 'Bluetooth conectado.' : 'No se pudo conectar después de varios intentos.';
    } catch (error) {
      _message = 'Error Bluetooth: $error';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _testBluetooth() async {
    try {
      await _service.printBluetoothTest();
      if (mounted) setState(() => _message = 'Prueba Bluetooth enviada.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Error de impresión Bluetooth: $error');
    }
  }

  Future<void> _testWifi() async {
    final port = int.tryParse(_portController.text) ?? 9100;
    if (_hostController.text.trim().isEmpty) return;
    setState(() { _loading = true; _message = null; });
    final result = await _service.printWifiTest(_hostController.text.trim(), port: port);
    if (mounted) setState(() { _loading = false; _message = result.msg; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impresoras')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Bluetooth', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _loading ? null : _scan, icon: const Icon(Icons.search), label: const Text('Buscar vinculadas')),
          ..._printers.map((printer) => ListTile(
            title: Text(printer.name),
            subtitle: Text(printer.macAdress),
            trailing: _connectedAddress == printer.macAdress ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.bluetooth),
            onTap: () => _connect(printer),
          )),
          if (_connectedAddress != null) FilledButton.icon(onPressed: _testBluetooth, icon: const Icon(Icons.print), label: const Text('Imprimir prueba Bluetooth')),
          const Divider(height: 32),
          const Text('WiFi / TCP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _hostController, decoration: const InputDecoration(labelText: 'IP de la impresora', hintText: '192.168.1.100')),
          TextField(controller: _portController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Puerto TCP')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _loading ? null : _testWifi, icon: const Icon(Icons.print), label: const Text('Conectar e imprimir prueba')),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
        ],
      ),
    );
  }
}
