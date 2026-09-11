import 'dart:async';
import 'dart:convert';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../storage/app_storage.dart';

/// ============================================================
/// CONFIGURACIÓN DEL TICKET
/// ============================================================

class TicketConfig {
  final String empresa;
  final String? rfc;
  final String? direccion;
  final String? telefono;
  final String? email;
  final String? encabezado;
  final String? pie;
  final String? logoPath;

  final PaperSize paperSize;

  final bool mostrarLogo;
  final bool mostrarDireccion;
  final bool mostrarTelefono;
  final bool mostrarEmail;
  final bool mostrarVendedor;
  final bool mostrarMetodoPago;
  final bool mostrarCambio;
  final bool mostrarFolio;
  final bool mostrarFecha;
  final bool cortarTicket;

  final int copies;

  final Map<String, bool> campos;

  final bool mostrarQr;

  final String? qrContenido;

  final String? fuente;

  final int tamanoFuente;

  final String alineacion;

  const TicketConfig({
    this.empresa = 'Mi Empresa',
    this.rfc,
    this.direccion,
    this.telefono,
    this.email,
    this.encabezado,
    this.pie = 'Gracias por su compra',
    this.logoPath,
    this.paperSize = PaperSize.mm58,
    this.mostrarLogo = false,
    this.mostrarDireccion = true,
    this.mostrarTelefono = true,
    this.mostrarEmail = false,
    this.mostrarVendedor = true,
    this.mostrarMetodoPago = true,
    this.mostrarCambio = true,
    this.mostrarFolio = true,
    this.mostrarFecha = true,
    this.cortarTicket = true,
    this.copies = 1,
    this.campos = const {},
    this.mostrarQr = false,
    this.qrContenido,
    this.fuente,
    this.tamanoFuente = 12,
    this.alineacion = 'izquierda',
  });

  factory TicketConfig.fromMap(
    Map<String, dynamic> source, {
    String? empresaFallback,
    String? direccionFallback,
    String? telefonoFallback,
  }) {
    final map = _unwrapConfig(
      source,
    );

    final papel = _string(
      map['papel'],
      fallback: '58mm',
    );

    final campos =
        _parseCampos(
      map['campos'],
    );

    final mostrarDireccion =
        campos.containsKey(
              'direccion',
            )
            ? campos['direccion']!
            : true;

    final mostrarTelefono =
        campos.containsKey(
              'telefono',
            )
            ? campos['telefono']!
            : true;

    final mostrarFecha =
        campos.containsKey(
              'fecha',
            )
            ? campos['fecha']!
            : true;

    final mostrarProductos =
        campos.containsKey(
              'productos',
            )
            ? campos['productos']!
            : true;

    final mostrarTotal =
        campos.containsKey(
              'total',
            )
            ? campos['total']!
            : true;

    final nombreNegocioVisible =
        campos.containsKey(
              'nombre_negocio',
            )
            ? campos[
                'nombre_negocio']!
            : true;

    final empresa =
        _string(
          map['nombre_negocio'] ??
              map['empresa'] ??
              map['nombreEmpresa'] ??
              empresaFallback,
        ).isNotEmpty
        ? _string(
            map['nombre_negocio'] ??
                map['empresa'] ??
                map['nombreEmpresa'] ??
                empresaFallback,
          )
        : 'Mi Empresa';

    final cabecera =
        _nullableString(
      map['cabecera'] ??
          map['encabezado'],
    );

    final pie =
        _nullableString(
      map['pie_pagina'] ??
          map['pie'],
    );

    final fuente =
        _nullableString(
      map['fuente'],
    );

    final tamanoFuente =
        _intValue(
          map['tamano_fuente'],
          fallback: 12,
        ).clamp(
          8,
          30,
        );

    final alineacion =
        _string(
          map['alineacion'],
          fallback: 'izquierda',
        ).toLowerCase();

    final mostrarLogo =
        _boolValue(
          map['mostrar_logo'],
          fallback: false,
        );

    final mostrarQr =
        _boolValue(
          map['mostrar_qr'],
          fallback: false,
        );

    final qrContenido =
        _nullableString(
      map['qr_contenido'],
    );

    return TicketConfig(
      empresa: empresa,
      rfc:
          _nullableString(
        map['rfc'],
      ),
      direccion:
          _nullableString(
            map['direccion'],
          ) ??
          direccionFallback,
      telefono:
          _nullableString(
            map['telefono'],
          ) ??
          telefonoFallback,
      email:
          _nullableString(
        map['email'],
      ),
      encabezado: cabecera,
      pie:
          pie ??
          'Gracias por su compra',
      logoPath:
          _nullableString(
        map['logo_path'] ??
            map['logoPath'] ??
            map['logo_url'] ??
            map['logoUrl'],
      ),
      paperSize:
          _paperSize(papel),
      mostrarLogo:
          mostrarLogo &&
          nombreNegocioVisible,
      mostrarDireccion:
          mostrarDireccion,
      mostrarTelefono:
          mostrarTelefono,
      mostrarEmail:
          _boolValue(
        map['mostrar_email'],
        fallback: false,
      ),
      mostrarVendedor:
          _boolValue(
        map['mostrar_vendedor'],
        fallback: true,
      ),
      mostrarMetodoPago:
          _boolValue(
        map['mostrar_metodo_pago'],
        fallback: true,
      ),
      mostrarCambio:
          _boolValue(
        map['mostrar_cambio'],
        fallback: true,
      ),
      mostrarFolio:
          _boolValue(
        map['mostrar_folio'],
        fallback: true,
      ),
      mostrarFecha:
          mostrarFecha,
      cortarTicket:
          _boolValue(
        map['cortar_ticket'],
        fallback: true,
      ),
      copies:
          _intValue(
            map['copies'] ??
                map['copias'],
            fallback: 1,
          ).clamp(
            1,
            10,
          ),
      campos: {
        ...campos,
        'nombre_negocio':
            nombreNegocioVisible,
        'direccion':
            mostrarDireccion,
        'telefono':
            mostrarTelefono,
        'fecha':
            mostrarFecha,
        'productos':
            mostrarProductos,
        'total':
            mostrarTotal,
      },
      mostrarQr:
          mostrarQr,
      qrContenido:
          qrContenido,
      fuente:
          fuente,
      tamanoFuente:
          tamanoFuente,
      alineacion:
          alineacion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'papel':
          paperSize ==
                  PaperSize.mm80
              ? '80mm'
              : '58mm',
      'fuente':
          fuente ??
              'Arial',
      'tamano_fuente':
          tamanoFuente,
      'alineacion':
          alineacion,
      'mostrar_logo':
          mostrarLogo,
      'mostrar_qr':
          mostrarQr,
      'qr_contenido':
          qrContenido,
      'campos':
          campos.entries.map(
        (entry) {
          return {
            'nombre':
                entry.key,
            'visible':
                entry.value,
          };
        },
      ).toList(),
      'cabecera':
          encabezado,
      'pie_pagina':
          pie,
    };
  }

  static Map<String, dynamic>
      _unwrapConfig(
    Map<String, dynamic> source,
  ) {
    final config =
        source['config'];

    if (config is Map) {
      return Map<String, dynamic>.from(
        config,
      );
    }

    return Map<String, dynamic>.from(
      source,
    );
  }

  static Map<String, bool>
      _parseCampos(
    dynamic value,
  ) {
    if (value is! List) {
      return {};
    }

    final entries =
        <Map<String, dynamic>>[];

    for (final item in value) {
      if (item is Map) {
        entries.add(
          Map<String, dynamic>.from(
            item,
          ),
        );
      }
    }

    entries.sort(
      (a, b) {
        final orderA =
            _intValue(
          a['orden'],
          fallback: 999,
        );

        final orderB =
            _intValue(
          b['orden'],
          fallback: 999,
        );

        return orderA.compareTo(
          orderB,
        );
      },
    );

    final result =
        <String, bool>{};

    for (final item in entries) {
      final name =
          _string(
        item['nombre'],
      );

      if (name.isEmpty) {
        continue;
      }

      result[name] =
          _boolValue(
        item['visible'],
        fallback: true,
      );
    }

    return result;
  }

  static PaperSize _paperSize(
    String value,
  ) {
    final normalized =
        value
            .toLowerCase()
            .replaceAll(
              ' ',
              '',
            );

    if (normalized
        .contains('80')) {
      return PaperSize.mm80;
    }

    return PaperSize.mm58;
  }

  static String _string(
    dynamic value, {
    String fallback = '',
  }) {
    if (value == null) {
      return fallback;
    }

    final result =
        value.toString().trim();

    return result.isEmpty
        ? fallback
        : result;
  }

  static String? _nullableString(
    dynamic value,
  ) {
    final result =
        _string(value);

    return result.isEmpty
        ? null
        : result;
  }

  static bool _boolValue(
    dynamic value, {
    bool fallback = false,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized =
        value
            .toString()
            .trim()
            .toLowerCase();

    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'si' ||
        normalized == 'sí' ||
        normalized == 'yes') {
      return true;
    }

    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no') {
      return false;
    }

    return fallback;
  }

  static int _intValue(
    dynamic value, {
    int fallback = 0,
  }) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value.toString(),
        ) ??
        fallback;
  }
}

/// ============================================================
/// INFORMACIÓN DE IMPRESORA BLUETOOTH
/// ============================================================

class PrinterDevice {
  final String name;
  final String address;
  final String alias;

  const PrinterDevice({
    required this.name,
    required this.address,
    required this.alias,
  });

  String get displayName {
    if (alias.trim().isNotEmpty) {
      return alias;
    }

    if (name.trim().isNotEmpty) {
      return name;
    }

    return address;
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'alias': alias,
    };
  }

  factory PrinterDevice.fromMap(
    Map<String, dynamic> map,
  ) {
    return PrinterDevice(
      name:
          map['name']
                  ?.toString() ??
              '',
      address:
          map['address']
                  ?.toString() ??
              '',
      alias:
          map['alias']
                  ?.toString() ??
              '',
    );
  }
}

/// ============================================================
/// RESULTADO DE IMPRESIÓN
/// ============================================================

class PrintOperationResult {
  final bool success;
  final String message;

  const PrintOperationResult({
    required this.success,
    required this.message,
  });

  factory PrintOperationResult.ok([
    String message =
        'Impresión realizada correctamente.',
  ]) {
    return PrintOperationResult(
      success: true,
      message: message,
    );
  }

  factory PrintOperationResult.error(
    String message,
  ) {
    return PrintOperationResult(
      success: false,
      message: message,
    );
  }
}

/// ============================================================
/// SERVICIO PRINCIPAL
/// ============================================================

class PrinterService {
  PrinterService({
    this.inactivityTimeout =
        const Duration(
      minutes: 30,
    ),
  });

  static const String
      _aliasesKey =
      'printer_aliases';

  static const String
      _selectedPrinterKey =
      'selected_printer_mac';

  final Duration
      inactivityTimeout;

  Timer? _inactivityTimer;

  String? _connectedAddress;

  bool _printing = false;

  bool _connecting = false;

  String? get connectedAddress =>
      _connectedAddress;

  bool get isPrinting =>
      _printing;

  /// ==========================================================
  /// CONFIGURACIÓN DE TICKET
  /// ==========================================================

  Future<TicketConfig>
      loadTicketConfig({
    String? empresa,
    String? direccion,
    String? telefono,
  }) async {
    final storage =
        AppStorage();

    try {
      final remote =
          await ApiClient()
              .getTicketConfig();

      final config =
          TicketConfig.fromMap(
        remote,
        empresaFallback:
            empresa,
        direccionFallback:
            direccion,
        telefonoFallback:
            telefono,
      );

      await storage
          .saveTicketConfig(
        config.toMap(),
      );

      return config;
    } catch (_) {
      final cached =
          await storage
              .getTicketConfig();

      if (cached.isNotEmpty) {
        return TicketConfig.fromMap(
          cached,
          empresaFallback:
              empresa,
          direccionFallback:
              direccion,
          telefonoFallback:
              telefono,
        );
      }

      return TicketConfig(
        empresa:
            empresa ??
                'Mi Empresa',
        direccion:
            direccion,
        telefono:
            telefono,
      );
    }
  }

  Future<TicketConfig>
      loadCachedTicketConfig({
    String? empresa,
    String? direccion,
    String? telefono,
  }) async {
    final cached =
        await AppStorage()
            .getTicketConfig();

    if (cached.isEmpty) {
      return TicketConfig(
        empresa:
            empresa ??
                'Mi Empresa',
        direccion:
            direccion,
        telefono:
            telefono,
      );
    }

    return TicketConfig.fromMap(
      cached,
      empresaFallback:
          empresa,
      direccionFallback:
          direccion,
      telefonoFallback:
          telefono,
    );
  }

  Future<void> saveTicketConfig(
    Map<String, dynamic> config,
  ) async {
    final normalized =
        TicketConfig.fromMap(
      config,
    );

    await AppStorage()
        .saveTicketConfig(
      normalized.toMap(),
    );
  }

  // ============================================================
  // IMPRESORAS BLUETOOTH
  // ============================================================

  Future<List<PrinterDevice>>
      pairedBluetoothPrinters() async {
    final printers =
        await PrintBluetoothThermal
            .pairedBluetooths;

    final aliases =
        await _loadAliases();

    return printers.map(
      (printer) {
        final address =
            printer.macAdress
                .trim();

        return PrinterDevice(
          name: printer.name.trim(),
          address: address,
          alias:
              aliases[address] ??
                  '',
        );
      },
    ).toList();
  }

  // ============================================================
  // ESTADO BLUETOOTH
  // ============================================================

  Future<bool> bluetoothEnabled() {
    return PrintBluetoothThermal
        .bluetoothEnabled;
  }

  Future<bool>
      bluetoothPermissionGranted() {
    return PrintBluetoothThermal
        .isPermissionBluetoothGranted;
  }

  Future<bool>
      bluetoothConnected() async {
    try {
      final connected =
          await PrintBluetoothThermal
              .connectionStatus;

      if (!connected) {
        _connectedAddress = null;
        _cancelInactivityTimer();
      }

      return connected;
    } catch (_) {
      _connectedAddress = null;
      _cancelInactivityTimer();
      return false;
    }
  }

  // ============================================================
  // ALIAS
  // ============================================================

  Future<void> setPrinterAlias(
    String address,
    String alias,
  ) async {
    final normalizedAddress =
        address.trim();

    if (normalizedAddress.isEmpty) {
      return;
    }

    final prefs =
        await SharedPreferences
            .getInstance();

    final aliases =
        await _loadAliases();

    final normalizedAlias =
        alias.trim();

    if (normalizedAlias.isEmpty) {
      aliases.remove(
        normalizedAddress,
      );
    } else {
      aliases[
              normalizedAddress] =
          normalizedAlias;
    }

    await prefs.setString(
      _aliasesKey,
      jsonEncode(aliases),
    );
  }

  Future<String?> getPrinterAlias(
    String address,
  ) async {
    final aliases =
        await _loadAliases();

    return aliases[
      address.trim()
    ];
  }

  Future<Map<String, String>>
      _loadAliases() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    final value =
        prefs.getString(
      _aliasesKey,
    );

    if (value == null ||
        value.isEmpty) {
      return {};
    }

    try {
      final decoded =
          jsonDecode(value);

      if (decoded is! Map) {
        return {};
      }

      return decoded.map(
        (key, value) =>
            MapEntry(
          key.toString(),
          value.toString(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  // ============================================================
  // IMPRESORA SELECCIONADA
  // ============================================================

  Future<void> selectPrinter(
    String address,
  ) async {
    final normalizedAddress =
        address.trim();

    if (normalizedAddress.isEmpty) {
      return;
    }

    final prefs =
        await SharedPreferences
            .getInstance();

    await prefs.setString(
      _selectedPrinterKey,
      normalizedAddress,
    );
  }

  Future<String?>
      selectedPrinterAddress() async {
    final prefs =
        await SharedPreferences
            .getInstance();

    return prefs.getString(
      _selectedPrinterKey,
    );
  }

  Future<PrinterDevice?>
      selectedPrinter() async {
    final address =
        await selectedPrinterAddress();

    if (address == null ||
        address.trim().isEmpty) {
      return null;
    }

    final normalizedAddress =
        address.trim().toLowerCase();

    final printers =
        await pairedBluetoothPrinters();

    for (final printer
        in printers) {
      if (printer.address
              .trim()
              .toLowerCase() ==
          normalizedAddress) {
        return printer;
      }
    }

    return null;
  }

  // ============================================================
  // CONEXIÓN BLUETOOTH
  // ============================================================

  Future<bool> connectBluetooth(
    String address, {
    int attempts = 3,
    Duration retryDelay =
        const Duration(
      milliseconds: 500,
    ),
  }) async {
    final normalizedAddress =
        address.trim();

    if (normalizedAddress.isEmpty) {
      return false;
    }

    _cancelInactivityTimer();

    for (
      var attempt = 0;
      attempt < attempts;
      attempt++
    ) {
      try {
        final alreadyConnected =
            await PrintBluetoothThermal
                .connectionStatus;

        if (alreadyConnected) {
          if (_connectedAddress ==
              normalizedAddress) {
            _restartInactivityTimer();

            return true;
          }

          await disconnectBluetooth();
        }

        final connected =
            await PrintBluetoothThermal
                .connect(
          macPrinterAddress:
              normalizedAddress,
        );

        if (connected) {
          _connectedAddress =
              normalizedAddress;

          await selectPrinter(
            normalizedAddress,
          );

          _restartInactivityTimer();

          return true;
        }
      } catch (_) {
        if (attempt ==
            attempts - 1) {
          rethrow;
        }
      }

      if (attempt <
          attempts - 1) {
        await Future<void>
            .delayed(
          retryDelay,
        );
      }
    }

    return false;
  }

  // ============================================================
  // RECONEXIÓN
  // ============================================================

  Future<bool>
      reconnectSelectedPrinter() async {
    final address =
        await selectedPrinterAddress();

    if (address == null ||
        address.isEmpty) {
      return false;
    }

    return connectBluetooth(
      address,
    );
  }

  Future<bool>
      ensureBluetoothConnection() async {
    if (_connecting) {
      return false;
    }

    final connected =
        await PrintBluetoothThermal
            .connectionStatus;

    if (connected) {
      return true;
    }

    final address =
        await selectedPrinterAddress();

    if (address == null ||
        address.trim().isEmpty) {
      return false;
    }

    _connecting = true;

    try {
      return await connectBluetooth(
        address,
      );
    } finally {
      _connecting = false;
    }
  }

  // ============================================================
  // SELECCIÓN Y CONEXIÓN
  // ============================================================

  Future<bool>
      selectAndConnectPrinter(
    String address,
  ) async {
    final normalizedAddress =
        address.trim();

    if (normalizedAddress.isEmpty) {
      return false;
    }

    return connectBluetooth(
      normalizedAddress,
    );
  }

  Future<List<PrinterDevice>>
      availablePrinters() async {
    return pairedBluetoothPrinters();
  }

  // ============================================================
  // DESCONEXIÓN
  // ============================================================

  Future<void>
      disconnectBluetooth() async {
    _cancelInactivityTimer();

    try {
      await PrintBluetoothThermal
          .disconnect;
    } finally {
      _connectedAddress = null;
    }
  }

  // ============================================================
  // DESCONEXIÓN AUTOMÁTICA
  // ============================================================

  void _restartInactivityTimer() {
    _cancelInactivityTimer();

    _inactivityTimer =
        Timer(
      inactivityTimeout,
      () async {
        try {
          final connected =
              await PrintBluetoothThermal
                  .connectionStatus;

          if (connected) {
            await disconnectBluetooth();
          }
        } catch (_) {
          _connectedAddress = null;
        }
      },
    );
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void touchConnection() {
    if (_connectedAddress != null) {
      _restartInactivityTimer();
    }
  }

  // ============================================================
  // ENVÍO BLUETOOTH
  // ============================================================

  Future<PrintOperationResult>
      _writeBytes(
    List<int> bytes,
  ) async {
    if (_printing) {
      return PrintOperationResult.error(
        'Ya existe una impresión en proceso.',
      );
    }

    _printing = true;

    try {
      final connected =
          await ensureBluetoothConnection();

      if (!connected) {
        return PrintOperationResult.error(
          'La impresora Bluetooth no está conectada y no fue posible reconectarla.',
        );
      }

      final result =
          await PrintBluetoothThermal
              .writeBytes(bytes);

      if (!result) {
        return PrintOperationResult.error(
          'La impresora rechazó los datos.',
        );
      }

      touchConnection();

      return PrintOperationResult.ok();
    } catch (e) {
      return PrintOperationResult.error(
        'Error al imprimir: $e',
      );
    } finally {
      _printing = false;
    }
  }

  // ============================================================
  // PRUEBA BLUETOOTH
  // ============================================================

  Future<PrintOperationResult>
      printBluetoothTest({
    TicketConfig config =
        const TicketConfig(),
  }) async {
    final profile =
        await CapabilityProfile
            .load();

    final generator =
        Generator(
      config.paperSize,
      profile,
    );

    final bytes =
        <int>[
      ...generator.reset(),

      ...generator.text(
        config.empresa,
        styles:
            const PosStyles(
          align:
              PosAlign.center,
          bold: true,
          height:
              PosTextSize.size2,
          width:
              PosTextSize.size2,
        ),
      ),

      ...generator.text(
        'PRUEBA DE IMPRESION',
        styles:
            const PosStyles(
          align:
              PosAlign.center,
          bold: true,
        ),
      ),

      ...generator.text(
        'Conexion Bluetooth OK',
        styles:
            const PosStyles(
          align:
              PosAlign.center,
        ),
      ),

      ...generator.feed(2),

      if (config.cortarTicket)
        ...generator.cut(),
    ];

    return _writeBytes(
      bytes,
    );
  }

  // ============================================================
  // WIFI / TCP
  // ============================================================

  Future<PrintOperationResult>
      printWifiTest(
    String host, {
    int port = 9100,
    int attempts = 3,
    Duration timeout =
        const Duration(
      seconds: 5,
    ),
    TicketConfig config =
        const TicketConfig(),
  }) async {
    final normalizedHost =
        host.trim();

    if (normalizedHost.isEmpty) {
      return PrintOperationResult.error(
        'La dirección IP de la impresora está vacía.',
      );
    }

    if (port <= 0 ||
        port > 65535) {
      return PrintOperationResult.error(
        'El puerto de la impresora no es válido.',
      );
    }

    if (attempts <= 0) {
      attempts = 1;
    }

    PosPrintResult result =
        PosPrintResult.timeout;

    for (
      var attempt = 0;
      attempt < attempts;
      attempt++
    ) {
      NetworkPrinter? printer;

      try {
        final profile =
            await CapabilityProfile
                .load();

        printer =
            NetworkPrinter(
          config.paperSize,
          profile,
        );

        result =
            await printer.connect(
          normalizedHost,
          port: port,
          timeout: timeout,
        );

        if (result ==
            PosPrintResult.success) {
          printer.text(
            config.empresa,
            styles:
                PosStyles(
              align:
                  PosAlign.center,
              bold: true,
              height:
                  PosTextSize.size2,
              width:
                  PosTextSize.size2,
            ),
          );

          printer.text(
            'PRUEBA DE IMPRESION',
            styles:
                PosStyles(
              align:
                  PosAlign.center,
              bold: true,
            ),
          );

          printer.text(
            'Conexion WiFi/TCP OK',
            styles:
                PosStyles(
              align:
                  PosAlign.center,
            ),
          );

          printer.text(
            'IP: $normalizedHost',
            styles:
                PosStyles(
              align:
                  PosAlign.center,
            ),
          );

          printer.text(
            'Puerto: $port',
            styles:
                PosStyles(
              align:
                  PosAlign.center,
            ),
          );

          printer.feed(2);

          if (config.cortarTicket) {
            printer.cut();
          }

          printer.disconnect();

          return PrintOperationResult.ok(
            'Conexión WiFi/TCP correcta.',
          );
        }
      } catch (e) {
        if (attempt ==
            attempts - 1) {
          return PrintOperationResult.error(
            'Error al imprimir por WiFi/TCP: $e',
          );
        }
      } finally {
        try {
          printer?.disconnect();
        } catch (_) {}
      }

      if (attempt <
          attempts - 1) {
        await Future<void>.delayed(
          Duration(
            milliseconds:
                300 *
                    (attempt + 1),
          ),
        );
      }
    }

    return PrintOperationResult.error(
      'No fue posible conectar con la impresora '
      'WiFi/TCP ($normalizedHost:$port). '
      'Resultado: $result',
    );
  }

  // ============================================================
  // VENTA
  // ============================================================

  Future<PrintOperationResult>
      printSale(
    Map<String, dynamic> sale, {
    TicketConfig? config,
  }) async {
    final effectiveConfig =
        config ??
        await loadCachedTicketConfig(
          empresa:
              _stringValue(
            sale,
            [
              'empresa',
              'nombreEmpresa',
              'companyName',
            ],
          ),
        );

    final bytes =
        await _buildSaleTicket(
      sale,
      config: effectiveConfig,
    );

    return _printCopies(
      bytes,
      effectiveConfig.copies,
    );
  }

  Future<PrintOperationResult>
      reprintSale(
    Map<String, dynamic> sale, {
    TicketConfig? config,
  }) {
    return printSale(
      sale,
      config: config,
    );
  }

  // ============================================================
  // INGRESO
  // ============================================================

  Future<PrintOperationResult>
      printIncome(
    Map<String, dynamic> movement, {
    TicketConfig? config,
  }) async {
    final effectiveConfig =
        config ??
        await loadCachedTicketConfig();

    final bytes =
        await _buildCashMovementTicket(
      movement,
      type: 'INGRESO',
      config: effectiveConfig,
    );

    return _printCopies(
      bytes,
      effectiveConfig.copies,
    );
  }

  Future<PrintOperationResult>
      reprintIncome(
    Map<String, dynamic> movement, {
    TicketConfig? config,
  }) {
    return printIncome(
      movement,
      config: config,
    );
  }

  // ============================================================
  // EGRESO
  // ============================================================

  Future<PrintOperationResult>
      printExpense(
    Map<String, dynamic> movement, {
    TicketConfig? config,
  }) async {
    final effectiveConfig =
        config ??
        await loadCachedTicketConfig();

    final bytes =
        await _buildCashMovementTicket(
      movement,
      type: 'EGRESO',
      config: effectiveConfig,
    );

    return _printCopies(
      bytes,
      effectiveConfig.copies,
    );
  }

  Future<PrintOperationResult>
      reprintExpense(
    Map<String, dynamic> movement, {
    TicketConfig? config,
  }) {
    return printExpense(
      movement,
      config: config,
    );
  }

  // ============================================================
  // COPIAS
  // ============================================================

  Future<PrintOperationResult>
      _printCopies(
    List<int> bytes,
    int copies,
  ) async {
    final totalCopies =
        copies <= 0
            ? 1
            : copies;

    for (
      var i = 0;
      i < totalCopies;
      i++
    ) {
      final result =
          await _writeBytes(
        bytes,
      );

      if (!result.success) {
        return result;
      }

      if (i <
          totalCopies - 1) {
        await Future<void>
            .delayed(
          const Duration(
            milliseconds: 300,
          ),
        );
      }
    }

    return PrintOperationResult.ok(
      totalCopies == 1
          ? 'Impresión realizada correctamente.'
          : '$totalCopies copias impresas correctamente.',
    );
  }

  // ============================================================
  // TICKET DE VENTA
  // ============================================================

  Future<List<int>>
      _buildSaleTicket(
    Map<String, dynamic> sale, {
    required TicketConfig config,
  }) async {
    final profile =
        await CapabilityProfile
            .load();

    final generator =
        Generator(
      config.paperSize,
      profile,
    );

    final bytes =
        <int>[
      ...generator.reset(),
    ];

    final mostrarNombreEmpresa =
        config.campos[
                'nombre_negocio'] ??
            true;

    if (mostrarNombreEmpresa) {
      bytes.addAll(
        generator.text(
          config.empresa,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
            height:
                PosTextSize.size2,
            width:
                PosTextSize.size2,
          ),
        ),
      );
    }

    if (config.mostrarLogo &&
        config.logoPath != null &&
        config.logoPath!
            .trim()
            .isNotEmpty) {
      // Reservado para procesamiento de imagen ESC/POS.
    }

    if (config.rfc != null &&
        config.rfc!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          'RFC: ${config.rfc}',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarDireccion &&
        config.direccion != null &&
        config.direccion!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.direccion!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarTelefono &&
        config.telefono != null &&
        config.telefono!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Tel: ${config.telefono}',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarEmail &&
        config.email != null &&
        config.email!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.email!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.hr(),
    );

    final encabezado =
        config.encabezado;

    if (encabezado != null &&
        encabezado
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          encabezado,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
          ),
        ),
      );
    } else {
      bytes.addAll(
        generator.text(
          'NOTA DE VENTA',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
          ),
        ),
      );
    }

    final folio =
        _stringValue(
      sale,
      [
        'folio',
        'numero',
        'saleNumber',
        'id',
      ],
    );

    final fecha =
        _stringValue(
      sale,
      [
        'fecha',
        'date',
        'createdAt',
      ],
    );

    final vendedor =
        _stringValue(
      sale,
      [
        'vendedor',
        'usuario',
        'sellerName',
      ],
    );

    if (config.mostrarFolio &&
        folio.isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Folio: $folio',
          styles:
              const PosStyles(
            bold: true,
          ),
        ),
      );
    }

    if (config.mostrarFecha &&
        fecha.isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Fecha: $fecha',
        ),
      );
    }

    if (config.mostrarVendedor &&
        vendedor.isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Vendedor: $vendedor',
        ),
      );
    }

    bytes.addAll(
      generator.hr(),
    );

    final mostrarProductos =
        config.campos[
                'productos'] ??
            true;

    if (mostrarProductos) {
      bytes.addAll(
        generator.row([
          PosColumn(
            text: 'CANT',
            width: 2,
            styles:
                const PosStyles(
              bold: true,
            ),
          ),
          PosColumn(
            text: 'PRODUCTO',
            width: 6,
            styles:
                const PosStyles(
              bold: true,
            ),
          ),
          PosColumn(
            text: 'TOTAL',
            width: 4,
            styles:
                const PosStyles(
              bold: true,
              align:
                  PosAlign.right,
            ),
          ),
        ]),
      );

      final items =
          _extractItems(
        sale,
      );

      for (final item
          in items) {
        final cantidad =
            _numberValue(
          item,
          [
            'cantidad',
            'quantity',
            'qty',
          ],
        );

        final producto =
            _stringValue(
          item,
          [
            'producto',
            'nombre',
            'name',
            'descripcion',
          ],
        );

        final precio =
            _numberValue(
          item,
          [
            'precio',
            'price',
            'unitPrice',
          ],
        );

        final total =
            _numberValue(
          item,
          [
            'total',
            'subtotal',
            'importe',
          ],
          fallback:
              cantidad *
                  precio,
        );

        bytes.addAll(
          generator.row([
            PosColumn(
              text:
                  _formatNumber(
                cantidad,
              ),
              width: 2,
            ),
            PosColumn(
              text: producto,
              width: 6,
            ),
            PosColumn(
              text:
                  _money(
                total,
              ),
              width: 4,
              styles:
                  const PosStyles(
                align:
                    PosAlign.right,
              ),
            ),
          ]),
        );

        bytes.addAll(
          generator.text(
            '  ${_formatNumber(cantidad)} x ${_money(precio)}',
            styles:
                const PosStyles(
              fontType:
                  PosFontType.fontB,
            ),
          ),
        );
      }

      bytes.addAll(
        generator.hr(),
      );
    }

    final subtotal =
        _numberValue(
      sale,
      ['subtotal'],
    );

    final descuento =
        _numberValue(
      sale,
      [
        'descuento',
        'discount',
      ],
    );

    final impuesto =
        _numberValue(
      sale,
      [
        'impuesto',
        'iva',
        'tax',
      ],
    );

    final total =
        _numberValue(
      sale,
      [
        'total',
        'totalVenta',
        'grandTotal',
      ],
    );

    bytes.addAll(
      _totalRow(
        generator,
        'Subtotal',
        subtotal,
      ),
    );

    if (descuento > 0) {
      bytes.addAll(
        _totalRow(
          generator,
          'Descuento',
          descuento,
        ),
      );
    }

    if (impuesto > 0) {
      bytes.addAll(
        _totalRow(
          generator,
          'Impuestos',
          impuesto,
        ),
      );
    }

    final mostrarTotal =
        config.campos[
                'total'] ??
            true;

    if (mostrarTotal) {
      bytes.addAll(
        _totalRow(
          generator,
          'TOTAL',
          total,
          bold: true,
        ),
      );
    }

    if (config
        .mostrarMetodoPago) {
      final payments =
          _extractPayments(
        sale,
      );

      if (payments.isNotEmpty) {
        bytes.addAll(
          generator.feed(1),
        );

        bytes.addAll(
          generator.text(
            'FORMA DE PAGO',
            styles:
                const PosStyles(
              bold: true,
            ),
          ),
        );

        for (final payment
            in payments) {
          final method =
              _paymentMethodValue(
            payment,
          );

          final amount =
              _numberValue(
            payment,
            [
              'amount',
              'monto',
              'importe',
              'total',
            ],
          );

          if (method.isEmpty ||
              amount <= 0) {
            continue;
          }

          bytes.addAll(
            generator.row([
              PosColumn(
                text: method,
                width: 7,
              ),
              PosColumn(
                text:
                    _money(
                  amount,
                ),
                width: 5,
                styles:
                    const PosStyles(
                  align:
                      PosAlign.right,
                ),
              ),
            ]),
          );
        }
      } else {
        final metodoPago =
            _stringValue(
          sale,
          [
            'metodoPago',
            'paymentMethod',
            'formaPago',
          ],
        );

        if (metodoPago
            .isNotEmpty) {
          bytes.addAll(
            generator.text(
              'FORMA DE PAGO',
              styles:
                  const PosStyles(
                bold: true,
              ),
            ),
          );

          bytes.addAll(
            generator.text(
              metodoPago,
            ),
          );
        }
      }
    }

    if (config.mostrarCambio) {
      final recibido =
          _numberValue(
        sale,
        [
          'cashReceived',
          'recibido',
          'montoRecibido',
        ],
      );

      final cambio =
          _numberValue(
        sale,
        [
          'changeDue',
          'cambio',
          'change',
        ],
      );

      if (recibido > 0) {
        bytes.addAll(
          generator.row([
            PosColumn(
              text:
                  'RECIBIDO',
              width: 7,
            ),
            PosColumn(
              text:
                  _money(
                recibido,
              ),
              width: 5,
              styles:
                  const PosStyles(
                align:
                    PosAlign.right,
              ),
            ),
          ]),
        );
      }

      if (cambio > 0) {
        bytes.addAll(
          generator.row([
            PosColumn(
              text:
                  'CAMBIO',
              width: 7,
              styles:
                  const PosStyles(
                bold: true,
              ),
            ),
            PosColumn(
              text:
                  _money(
                cambio,
              ),
              width: 5,
              styles:
                  const PosStyles(
                align:
                    PosAlign.right,
                bold: true,
              ),
            ),
          ]),
        );
      }
    }

    if (config.mostrarQr &&
        config.qrContenido != null &&
        config.qrContenido!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.feed(1),
      );

      bytes.addAll(
        generator.text(
          'QR:',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          config.qrContenido!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.feed(1),
    );

    if (config.pie != null &&
        config.pie!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.pie!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.feed(2),
    );

    if (config.cortarTicket) {
      bytes.addAll(
        generator.cut(),
      );
    }

    return bytes;
  }

  // ============================================================
  // TICKET INGRESO / EGRESO
  // ============================================================

  Future<List<int>>
      _buildCashMovementTicket(
    Map<String, dynamic> movement, {
    required String type,
    required TicketConfig config,
  }) async {
    final profile =
        await CapabilityProfile
            .load();

    final generator =
        Generator(
      config.paperSize,
      profile,
    );

    final bytes =
        <int>[
      ...generator.reset(),
    ];

    if (config.campos[
            'nombre_negocio'] ??
        true) {
      bytes.addAll(
        generator.text(
          config.empresa,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
            height:
                PosTextSize.size2,
            width:
                PosTextSize.size2,
          ),
        ),
      );
    }

    if (config.rfc != null &&
        config.rfc!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          'RFC: ${config.rfc}',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarDireccion &&
        config.direccion != null &&
        config.direccion!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.direccion!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarTelefono &&
        config.telefono != null &&
        config.telefono!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Tel: ${config.telefono}',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    if (config.mostrarEmail &&
        config.email != null &&
        config.email!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.email!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.hr(),
    );

    if (config.encabezado != null &&
        config.encabezado!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.encabezado!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.text(
        type,
        styles:
            const PosStyles(
          align:
              PosAlign.center,
          bold: true,
          height:
              PosTextSize.size2,
        ),
      ),
    );

    final folio =
        _stringValue(
      movement,
      [
        'folio',
        'numero',
        'id',
      ],
    );

    final fecha =
        _stringValue(
      movement,
      [
        'fecha',
        'date',
        'createdAt',
      ],
    );

    final concepto =
        _stringValue(
      movement,
      [
        'concepto',
        'descripcion',
        'description',
        'motivo',
      ],
    );

    final usuario =
        _stringValue(
      movement,
      [
        'usuario',
        'vendedor',
        'userName',
      ],
    );

    final monto =
        _numberValue(
      movement,
      [
        'monto',
        'importe',
        'amount',
        'total',
      ],
    );

    if (folio.isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Folio: $folio',
        ),
      );
    }

    final mostrarFecha =
        config.campos[
                'fecha'] ??
            config.mostrarFecha;

    if (mostrarFecha &&
        fecha.isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Fecha: $fecha',
        ),
      );
    }

    if (usuario.isNotEmpty &&
        config.mostrarVendedor) {
      bytes.addAll(
        generator.text(
          'Usuario: $usuario',
        ),
      );
    }

    bytes.addAll(
      generator.hr(),
    );

    if (concepto
        .isNotEmpty) {
      bytes.addAll(
        generator.text(
          'Concepto:',
          styles:
              const PosStyles(
            bold: true,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          concepto,
        ),
      );
    }

    bytes.addAll(
      generator.hr(),
    );

    bytes.addAll(
      _totalRow(
        generator,
        'MONTO',
        monto,
        bold: true,
      ),
    );

    if (config.mostrarQr &&
        config.qrContenido != null &&
        config.qrContenido!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.feed(1),
      );

      bytes.addAll(
        generator.text(
          'QR:',
          styles:
              const PosStyles(
            align:
                PosAlign.center,
            bold: true,
          ),
        ),
      );

      bytes.addAll(
        generator.text(
          config.qrContenido!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.feed(2),
    );

    if (config.pie != null &&
        config.pie!
            .trim()
            .isNotEmpty) {
      bytes.addAll(
        generator.text(
          config.pie!,
          styles:
              const PosStyles(
            align:
                PosAlign.center,
          ),
        ),
      );
    }

    bytes.addAll(
      generator.feed(2),
    );

    if (config.cortarTicket) {
      bytes.addAll(
        generator.cut(),
      );
    }

    return bytes;
  }

  // ============================================================
  // FILA DE TOTAL
  // ============================================================

  List<int> _totalRow(
    Generator generator,
    String label,
    double value, {
    bool bold = false,
  }) {
    return generator.row([
      PosColumn(
        text: label,
        width: 7,
        styles:
            PosStyles(
          bold: bold,
        ),
      ),
      PosColumn(
        text:
            _money(value),
        width: 5,
        styles:
            PosStyles(
          align:
              PosAlign.right,
          bold: bold,
        ),
      ),
    ]);
  }

  // ============================================================
  // OBTENER DETALLES DE VENTA
  // ============================================================

  List<Map<String, dynamic>>
      _extractItems(
    Map<String, dynamic> sale,
  ) {
    final possibleItems = [
      sale['detalles'],
      sale['detalle'],
      sale['items'],
      sale['productos'],
      sale['details'],
    ];

    for (final value
        in possibleItems) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map(
              (item) =>
                  Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();
      }
    }

    return [];
  }

  // ============================================================
  // OBTENER PAGOS
  // ============================================================

  List<Map<String, dynamic>>
      _extractPayments(
    Map<String, dynamic> sale,
  ) {
    final possiblePayments = [
      sale['payments'],
      sale['pagos'],
      sale['sale_payments'],
      sale['paymentDetails'],
      sale['payment_details'],
    ];

    for (final value
        in possiblePayments) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map(
              (payment) =>
                  Map<String, dynamic>.from(
                payment,
              ),
            )
            .where(
              (payment) {
                final method = (
                  payment['method'] ??
                  payment['metodo'] ??
                  payment['metodoPago'] ??
                  payment['formaPago'] ??
                  ''
                ).toString().trim();

                final amount =
                    _numberValue(
                  payment,
                  [
                    'amount',
                    'monto',
                    'importe',
                    'total',
                  ],
                );

                return method.isNotEmpty &&
                    amount > 0;
              },
            )
            .toList();
      }
    }

    return [];
  }

  String _paymentMethodValue(
    Map<String, dynamic> payment,
  ) {
    return _stringValue(
      payment,
      [
        'method',
        'metodo',
        'metodoPago',
        'formaPago',
        'paymentMethod',
      ],
    );
  }

  // ============================================================
  // OBTENER STRING
  // ============================================================

  String _stringValue(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value =
          map[key];

      if (value == null) {
        continue;
      }

      final text =
          value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  // ============================================================
  // OBTENER NÚMERO
  // ============================================================

  double _numberValue(
    Map<String, dynamic> map,
    List<String> keys, {
    double fallback = 0,
  }) {
    for (final key in keys) {
      final value =
          map[key];

      if (value == null) {
        continue;
      }

      if (value is num) {
        return value.toDouble();
      }

      final parsed =
          double.tryParse(
        value
            .toString()
            .replaceAll(
              ',',
              '',
            ),
      );

      if (parsed != null) {
        return parsed;
      }
    }

    return fallback;
  }

  // ============================================================
  // FORMATO NÚMERO
  // ============================================================

  String _formatNumber(
    double value,
  ) {
    if (value ==
        value.roundToDouble()) {
      return value
          .toInt()
          .toString();
    }

    return value
        .toStringAsFixed(2);
  }

  // ============================================================
  // FORMATO DINERO
  // ============================================================

  String _money(
    double value,
  ) {
    return '\$${value.toStringAsFixed(2)}';
  }

  // ============================================================
  // LIMPIEZA
  // ============================================================

  Future<void> dispose() async {
    _cancelInactivityTimer();
    _connectedAddress = null;
  }
}