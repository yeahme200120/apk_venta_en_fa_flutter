import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:punto_venta_flutter/core/models/sale_model.dart';
import 'package:punto_venta_flutter/core/services/printer_service.dart';
import 'package:punto_venta_flutter/presentation/ventas/ticket_preview_screen.dart';

void main() {
  group('TicketPreviewScreen', () {
    testWidgets('muestra un ticket vacío correctamente', (tester) async {
      final sale = _buildSale();

      final config = _buildConfig();

      await tester.pumpWidget(_buildApp(sale: sale, config: config));

      expect(find.text('Vista previa del ticket'), findsOneWidget);
      expect(find.text('Mi Empresa'), findsOneWidget);
      expect(find.text('NOTA DE VENTA'), findsOneWidget);
      expect(find.text('Sin productos'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('\$0.00'), findsWidgets);
    });

    testWidgets('muestra productos, totales y pagos', (tester) async {
      final sale = _buildSale(
        total: 170.0,
        items: [
          SaleItemModel(
            id: 1,
            saleId: 1,
            productId: 10,
            name: 'Producto de prueba',
            quantity: 2,
            unitPrice: 85.0,
            total: 170.0,
          ),
        ],
        payments: [
          SalePaymentModel(id: 1, saleId: 1, method: 'Efectivo', amount: 170.0),
        ],
      );

      final config = _buildConfig();

      await tester.pumpWidget(_buildApp(sale: sale, config: config));

      expect(find.text('Producto de prueba'), findsOneWidget);
      expect(find.text('CANT'), findsOneWidget);
      expect(find.text('PRODUCTO'), findsOneWidget);
      expect(find.text('TOTAL'), findsWidgets);

      expect(find.text('\$170.00'), findsNWidgets(5));

      expect(find.text('FORMA DE PAGO'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
    });

    testWidgets('respeta campos opcionales desactivados', (tester) async {
      final sale = _buildSale(
        total: 100.0,
        items: [
          SaleItemModel(
            id: 1,
            saleId: 1,
            productId: 10,
            name: 'Producto oculto',
            quantity: 1,
            unitPrice: 100.0,
            total: 100.0,
          ),
        ],
      );

      final config = _buildConfig(
        rfc: 'ABC010101ABC',
        direccion: 'Dirección de prueba',
        telefono: '5555555555',
        email: 'correo@prueba.com',
        mostrarDireccion: false,
        mostrarTelefono: false,
        mostrarEmail: false,
        mostrarFolio: false,
        mostrarFecha: false,
        mostrarMetodoPago: false,
        mostrarCambio: false,
      );

      await tester.pumpWidget(_buildApp(sale: sale, config: config));

      expect(find.text('Mi Empresa'), findsOneWidget);
      expect(find.text('Producto oculto'), findsOneWidget);

      expect(find.text('RFC: ABC010101ABC'), findsOneWidget);

      expect(find.text('Dirección de prueba'), findsNothing);
      expect(find.text('Tel: 5555555555'), findsNothing);
      expect(find.text('correo@prueba.com'), findsNothing);

      expect(find.text('Folio:'), findsNothing);
      expect(find.text('Fecha:'), findsNothing);
      expect(find.text('FORMA DE PAGO'), findsNothing);
    });

    testWidgets('no falla cuando el logo local no existe', (tester) async {
      const missingPath = 'C:\\ruta\\inexistente\\ticket_logo_inexistente.webp';
      final sale = _buildSale();
      final config = _buildConfig(logoPath: missingPath, mostrarLogo: true);
      await tester.pumpWidget(_buildApp(sale: sale, config: config));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('ticket_preview_paper')), findsOneWidget);
      expect(find.text('Mi Empresa'), findsOneWidget);
      expect(find.text('NOTA DE VENTA'), findsOneWidget);
    });

    testWidgets('usa ancho de papel de 58mm', (tester) async {
      final sale = _buildSale();

      final config = _buildConfig(paperSize: PaperSize.mm58);

      await tester.pumpWidget(_buildApp(sale: sale, config: config));

      final paperFinder = find.byKey(const Key('ticket_preview_paper'));

      expect(paperFinder, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(paperFinder);

      expect(renderBox.size.width, 300);
    });

    testWidgets('usa ancho de papel de 80mm', (tester) async {
      final sale = _buildSale();

      final config = _buildConfig(paperSize: PaperSize.mm80);

      await tester.pumpWidget(_buildApp(sale: sale, config: config));

      final paperFinder = find.byKey(const Key('ticket_preview_paper'));

      expect(paperFinder, findsOneWidget);

      final renderBox = tester.renderObject<RenderBox>(paperFinder);

      expect(renderBox.size.width, 384);
    });
  });
}

Widget _buildApp({required SaleModel sale, required TicketConfig config}) {
  return MaterialApp(
    home: TicketPreviewScreen(sale: sale, config: config),
  );
}

SaleModel _buildSale({
  double total = 0.0,
  List<SaleItemModel> items = const [],
  List<SalePaymentModel> payments = const [],
}) {
  return SaleModel(
    id: 1,
    uuidLocal: 'sale-test-001',
    serverId: null,
    businessDate: '2026-09-11',
    total: total,
    syncStatus: 'pending',
    status: 'paid',
    folio: 'F-0001',
    items: items,
    payments: payments,
    createdAt: '2026-09-11T12:00:00.000',
    updatedAt: '2026-09-11T12:00:00.000',
  );
}

TicketConfig _buildConfig({
  String empresa = 'Mi Empresa',
  String? rfc,
  String? direccion,
  String? telefono,
  String? email,
  String? logoPath,
  String? encabezado,
  String? pie,
  PaperSize paperSize = PaperSize.mm80,
  bool mostrarLogo = false,
  bool mostrarDireccion = true,
  bool mostrarTelefono = true,
  bool mostrarEmail = true,
  bool mostrarFolio = true,
  bool mostrarFecha = true,
  bool mostrarVendedor = true,
  bool mostrarMetodoPago = true,
  bool mostrarCambio = true,
  Map<String, bool> campos = const {},
}) {
  return TicketConfig(
    empresa: empresa,
    rfc: rfc,
    direccion: direccion,
    telefono: telefono,
    email: email,
    logoPath: logoPath,
    encabezado: encabezado,
    pie: pie,
    paperSize: paperSize,
    mostrarLogo: mostrarLogo,
    mostrarDireccion: mostrarDireccion,
    mostrarTelefono: mostrarTelefono,
    mostrarEmail: mostrarEmail,
    mostrarFolio: mostrarFolio,
    mostrarFecha: mostrarFecha,
    mostrarVendedor: mostrarVendedor,
    mostrarMetodoPago: mostrarMetodoPago,
    mostrarCambio: mostrarCambio,
    campos: campos,
  );
}
