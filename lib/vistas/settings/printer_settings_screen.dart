import 'package:flutter/material.dart';

import '../../core/services/printer_service.dart';
import '../../core/services/permission_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrinterService _service = PrinterService();

  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '9100',
  );

  List<PrinterDevice> _printers = [];

  String? _selectedAddress;
  String? _connectedAddress;

  bool _loading = false;
  bool _printingTest = false;
  bool _bluetoothEnabled = false;
  bool _bluetoothPermission = false;

  String? _message;
  bool _messageError = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();

    // IMPORTANTE:
    // No desconectamos aquí la impresora.
    // La conexión puede ser utilizada posteriormente desde POS.
    super.dispose();
  }

  // ============================================================
  // INICIALIZACIÓN
  // ============================================================

  Future<void> _initialize() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _selectedAddress = await _service.selectedPrinterAddress();

      _bluetoothEnabled = await _service.bluetoothEnabled();

      _bluetoothPermission = await _service.bluetoothPermissionGranted();

      if (_bluetoothPermission && _bluetoothEnabled) {
        _printers = await _service.pairedBluetoothPrinters();

        final selectedPrinter = await _service.selectedPrinter();

        if (selectedPrinter != null) {
          final connected =
              await _service.ensureBluetoothConnection();

          if (connected) {
            _connectedAddress = selectedPrinter.address;
          }
        }
      }
    } catch (error) {
      _showMessage('No fue posible inicializar Bluetooth: $error', error: true);
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  // ============================================================
  // BLUETOOTH
  // ============================================================

  Future<void> _refreshBluetooth() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      _bluetoothEnabled = await _service.bluetoothEnabled();

      _bluetoothPermission = await _service.bluetoothPermissionGranted();

      if (!_bluetoothPermission) {
        final granted = await PermissionService().requestBluetoothPermissions();

        _bluetoothPermission = granted;

        if (!granted) {
          throw Exception(
            'Se requieren permisos Bluetooth para consultar las impresoras.',
          );
        }
      }

      if (!_bluetoothEnabled) {
        throw Exception(
          'Bluetooth está desactivado. Actívalo desde los ajustes del dispositivo.',
        );
      }

      // 1. Buscar impresoras vinculadas
      _printers = await _service.pairedBluetoothPrinters();

      // 2. Recuperar la impresora seleccionada
      _selectedAddress = await _service.selectedPrinterAddress();

      _connectedAddress = null;

      // 3. Si existe una impresora seleccionada,
      //    intentar conectarla automáticamente.
      if (_selectedAddress != null && _selectedAddress!.trim().isNotEmpty) {
        PrinterDevice? selectedPrinter;

        for (final printer in _printers) {
          if (printer.address.trim().toLowerCase() ==
              _selectedAddress!.trim().toLowerCase()) {
            selectedPrinter = printer;
            break;
          }
        }

        if (selectedPrinter != null) {
          try {
            final connected = await _service.connectBluetooth(
              selectedPrinter.address,
            );

            if (connected) {
              _connectedAddress = selectedPrinter.address;

              _showMessage(
                'Impresora encontrada y conectada: '
                '${selectedPrinter.displayName}.',
              );
            } else {
              _showMessage(
                'Impresora encontrada, pero no fue posible conectarla.',
                error: true,
              );
            }
          } catch (error) {
            _connectedAddress = null;

            _showMessage(
              'Impresora encontrada, pero no fue posible conectarla: $error',
              error: true,
            );
          }
        } else {
          _showMessage(
            _printers.isEmpty
                ? 'No hay impresoras Bluetooth vinculadas.'
                : 'Se encontraron ${_printers.length} impresora(s), '
                      'pero la impresora seleccionada ya no está vinculada.',
            error: true,
          );
        }
      } else {
        // No existe impresora seleccionada todavía.
        _showMessage(
          _printers.isEmpty
              ? 'No hay impresoras Bluetooth vinculadas.'
              : 'Se encontraron ${_printers.length} impresora(s). '
                    'Selecciona una impresora para utilizarla.',
        );
      }
    } catch (error) {
      _showMessage(
        'No se pudieron consultar las impresoras: $error',
        error: true,
      );
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _selectPrinter(PrinterDevice printer) async {
    try {
      await _service.selectPrinter(printer.address);

      if (!mounted) return;

      setState(() {
        _selectedAddress = printer.address;
      });

      _showMessage('Impresora seleccionada: ${printer.displayName}');
    } catch (error) {
      _showMessage(
        'No fue posible seleccionar la impresora: $error',
        error: true,
      );
    }
  }

  Future<void> _connectPrinter(PrinterDevice printer) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await _service.selectPrinter(printer.address);

      final connected = await _service.connectBluetooth(printer.address);

      if (!connected) {
        throw Exception('La impresora rechazó la conexión.');
      }

      _selectedAddress = printer.address;
      _connectedAddress = printer.address;

      _showMessage('Conectado correctamente a ${printer.displayName}.');
    } catch (error) {
      _connectedAddress = null;

      _showMessage(
        'No fue posible conectar con ${printer.displayName}: $error',
        error: true,
      );
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _disconnectPrinter() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await _service.disconnectBluetooth();

      _connectedAddress = null;

      _showMessage('Impresora desconectada.');
    } catch (error) {
      _showMessage(
        'No fue posible desconectar la impresora: $error',
        error: true,
      );
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  // ============================================================
  // PRUEBA BLUETOOTH
  // ============================================================

  Future<void> _testBluetooth() async {
    if (_printingTest) return;

    final connected =
        await _service.ensureBluetoothConnection();

    if (!connected) {
      _connectedAddress = null;

      _showMessage(
        'No fue posible conectar la impresora Bluetooth seleccionada.',
        error: true,
      );
      return;
    }

    final selectedPrinter = await _service.selectedPrinter();

    if (selectedPrinter == null) {
      _connectedAddress = null;

      _showMessage(
        'No hay una impresora Bluetooth seleccionada.',
        error: true,
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _connectedAddress = selectedPrinter.address;
      _printingTest = true;
      _message = null;
    });

    try {
      final result = await _service.printBluetoothTest();

      if (result.success) {
        _showMessage(
          result.message.isEmpty
              ? 'Prueba de impresión enviada correctamente.'
              : result.message,
        );
      } else {
        _showMessage(result.message, error: true);
      }
    } catch (error) {
      _showMessage('Error de impresión Bluetooth: $error', error: true);
    }

    if (!mounted) return;

    setState(() {
      _printingTest = false;
    });
  }

  // ============================================================
  // ALIAS
  // ============================================================

  Future<void> _editAlias(PrinterDevice printer) async {
    final controller = TextEditingController(text: printer.alias);

    final alias = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nombre de la impresora'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre personalizado',
              hintText: 'Ej. Impresora Caja 1',
              prefixIcon: Icon(Icons.label_outline),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (alias == null) return;

    try {
      await _service.setPrinterAlias(printer.address, alias);

      await _refreshBluetooth();
    } catch (error) {
      _showMessage('No fue posible guardar el nombre: $error', error: true);
    }
  }

  // ============================================================
  // WIFI
  // ============================================================

  Future<void> _testWifi() async {
    final host = _hostController.text.trim();

    if (host.isEmpty) {
      _showMessage('Ingresa la IP de la impresora.', error: true);
      return;
    }

    final port = int.tryParse(_portController.text.trim()) ?? 9100;

    if (port < 1 || port > 65535) {
      _showMessage('El puerto debe estar entre 1 y 65535.', error: true);
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final result = await _service.printWifiTest(host, port: port);

      _showMessage(result.message, error: !result.success);
    } catch (error) {
      _showMessage('Error de impresión WiFi: $error', error: true);
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  // ============================================================
  // MENSAJES
  // ============================================================

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;

    setState(() {
      _message = message;
      _messageError = error;
    });
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresoras'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _refreshBluetooth,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshBluetooth,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildConnectionStatus(cs),

            const SizedBox(height: 16),

            _buildBluetoothSection(cs),

            const SizedBox(height: 20),

            _buildWifiSection(cs),

            const SizedBox(height: 20),

            if (_message != null) _buildMessage(cs),

            const SizedBox(height: 20),

            _buildInformationCard(cs),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ESTADO DE CONEXIÓN
  // ============================================================

  Widget _buildConnectionStatus(ColorScheme cs) {
    final connected = _connectedAddress != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            connected ? cs.primaryContainer : cs.surfaceContainerHighest,
            cs.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? cs.primary.withValues(alpha: 0.35)
              : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: connected ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              connected ? Icons.print_outlined : Icons.print_disabled_outlined,
              color: connected ? cs.onPrimary : cs.onSurfaceVariant,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Impresora conectada' : 'Sin impresora conectada',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? _connectedPrinterName()
                      : 'Selecciona una impresora Bluetooth para comenzar.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (connected)
            IconButton(
              tooltip: 'Desconectar',
              onPressed: _loading ? null : _disconnectPrinter,
              icon: const Icon(Icons.link_off_outlined),
            ),
        ],
      ),
    );
  }

  String _connectedPrinterName() {
    for (final printer in _printers) {
      if (printer.address == _connectedAddress) {
        return printer.displayName;
      }
    }

    return _connectedAddress ?? 'Bluetooth';
  }

  // ============================================================
  // BLUETOOTH SECTION
  // ============================================================

  Widget _buildBluetoothSection(ColorScheme cs) {
    return _sectionCard(
      title: 'Bluetooth',
      subtitle: 'Administra las impresoras vinculadas al dispositivo.',
      icon: Icons.bluetooth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBluetoothState(cs),

          const SizedBox(height: 14),

          FilledButton.icon(
            onPressed: _loading ? null : _refreshBluetooth,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              _loading ? 'Buscando y conectando...' : 'Buscar y conectar impresora',
            ),
          ),

          const SizedBox(height: 14),

          if (_printers.isEmpty)
            _buildEmptyPrinters(cs)
          else
            ..._printers.map((printer) => _buildPrinterTile(cs, printer)),

          if (_connectedAddress != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _printingTest ? null : _testBluetooth,
              icon: _printingTest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_outlined),
              label: Text(_printingTest ? 'Imprimiendo...' : 'Imprimir prueba'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBluetoothState(ColorScheme cs) {
    final enabled = _bluetoothEnabled;
    final permission = _bluetoothPermission;

    Color iconColor;
    IconData icon;

    if (!permission) {
      iconColor = cs.error;
      icon = Icons.lock_outline;
    } else if (!enabled) {
      iconColor = cs.error;
      icon = Icons.bluetooth_disabled;
    } else {
      iconColor = cs.primary;
      icon = Icons.bluetooth_connected;
    }

    String text;

    if (!permission) {
      text = 'Permiso Bluetooth requerido';
    } else if (!enabled) {
      text = 'Bluetooth está desactivado';
    } else {
      text = 'Bluetooth disponible';
    }

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: iconColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPrinters(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(Icons.print_disabled_outlined, size: 36),
          SizedBox(height: 10),
          Text(
            'No hay impresoras vinculadas',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 5),
          Text(
            'Primero vincula la impresora desde los ajustes Bluetooth de Android y después pulsa "Buscar impresoras vinculadas".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PRINTER TILE
  // ============================================================

  Widget _buildPrinterTile(ColorScheme cs, PrinterDevice printer) {
    final selected = _selectedAddress == printer.address;

    final connected = _connectedAddress == printer.address;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? cs.primary.withValues(alpha: 0.45)
              : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectPrinter(printer),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: connected ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  connected ? Icons.print : Icons.print_outlined,
                  color: connected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            printer.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (selected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'SELECCIONADA',
                              style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      printer.address,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: cs.primary),
                          const SizedBox(width: 5),
                          Text(
                            'Conectada',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (value) {
                  if (value == 'alias') {
                    _editAlias(printer);
                  } else if (value == 'connect') {
                    _connectPrinter(printer);
                  } else if (value == 'select') {
                    _selectPrinter(printer);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'connect',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.bluetooth_connected),
                      title: Text('Conectar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'select',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Seleccionar'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'alias',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Cambiar nombre'),
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

  // ============================================================
  // WIFI SECTION
  // ============================================================

  Widget _buildWifiSection(ColorScheme cs) {
    return _sectionCard(
      title: 'WiFi / TCP',
      subtitle: 'Conecta una impresora de red mediante TCP/IP.',
      icon: Icons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _hostController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'IP de la impresora',
              hintText: '192.168.1.100',
              prefixIcon: Icon(Icons.router_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Puerto TCP',
              hintText: '9100',
              prefixIcon: Icon(Icons.settings_ethernet),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _testWifi,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Conectar e imprimir prueba'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  Widget _buildMessage(ColorScheme cs) {
    final color = _messageError ? cs.error : cs.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _messageError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFORMATION
  // ============================================================

  Widget _buildInformationCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 19),
              SizedBox(width: 8),
              Text('Importante', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'La impresora debe estar vinculada previamente en Android. '
            'Esta pantalla administra la conexión de la aplicación.',
            style: TextStyle(fontSize: 12, height: 1.45),
          ),
          SizedBox(height: 7),
          Text(
            'La impresora seleccionada se guarda en el dispositivo '
            'para utilizarla posteriormente desde el punto de venta.',
            style: TextStyle(fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CARD GENERAL
  // ============================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}