import 'dart:async';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterService {
  Future<List<BluetoothInfo>> pairedBluetoothPrinters() {
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> bluetoothConnected() {
    return PrintBluetoothThermal.connectionStatus;
  }

  Future<bool> connectBluetooth(String address, {int attempts = 3}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        if (await PrintBluetoothThermal.connect(macPrinterAddress: address)) return true;
      } catch (_) {
        if (attempt == attempts - 1) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return false;
  }

  Future<void> disconnectBluetooth() async {
    await PrintBluetoothThermal.disconnect;
  }

  Future<void> printBluetoothTest() async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[
      ...generator.reset(),
      ...generator.text('Prueba de impresion', styles: const PosStyles(align: PosAlign.center, bold: true)),
      ...generator.text('Conexion Bluetooth OK', styles: const PosStyles(align: PosAlign.center)),
      ...generator.feed(2),
      ...generator.cut(),
    ];
    if (!await PrintBluetoothThermal.writeBytes(bytes)) {
      throw Exception('La impresora Bluetooth rechazo los datos.');
    }
  }

  Future<PosPrintResult> connectWifi(String host, {int port = 9100, Duration timeout = const Duration(seconds: 5)}) async {
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(PaperSize.mm58, profile);
    return printer.connect(host, port: port, timeout: timeout);
  }

  Future<PosPrintResult> printWifiTest(String host, {int port = 9100, int attempts = 3}) async {
    PosPrintResult result = PosPrintResult.timeout;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm58, profile);
      result = await printer.connect(host, port: port, timeout: const Duration(seconds: 5));
      if (result == PosPrintResult.success) {
        printer.text('Prueba de impresion', styles: PosStyles(align: PosAlign.center, bold: true));
        printer.text('Conexion WiFi/TCP OK', styles: PosStyles(align: PosAlign.center));
        printer.feed(2);
        printer.cut();
        printer.disconnect();
        return result;
      }
      if (attempt < attempts - 1) await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return result;
  }
}
