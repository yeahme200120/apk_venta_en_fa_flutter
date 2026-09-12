import 'package:flutter_test/flutter_test.dart';

import 'package:punto_venta_flutter/core/models/sale_model.dart';
import 'package:punto_venta_flutter/core/models/ticket_data.dart';
import 'package:punto_venta_flutter/core/services/printer_service.dart';

void main() {
  group('TicketData', () {
    late TicketConfig config;

    setUp(() {
      config = TicketConfig(
        empresa: 'Mi Empresa',
        rfc: 'ABC123456XYZ',
        direccion: 'Av. Principal 123',
        telefono: '7351234567',
        email: 'ventas@empresa.com',
        encabezado: 'Gracias por su compra',
        pie: 'Vuelva pronto',
        logoPath: '/tmp/logo.webp',
        mostrarLogo: true,
        mostrarDireccion: true,
        mostrarTelefono: true,
        mostrarEmail: true,
        mostrarVendedor: true,
        mostrarMetodoPago: true,
        mostrarCambio: true,
        mostrarFolio: true,
        mostrarFecha: true,
        campos: {
          'nombre_negocio': true,
          'productos': true,
          'total': true,
          'fecha': true,
        },
      );
    });

    test(
      'construye TicketData correctamente desde una venta',
      () {
        final sale = SaleModel(
          id: 1,
          uuidLocal: 'uuid-local-001',
          serverId: 25,
          businessDate: '2026-09-11',
          total: 150.00,
          syncStatus: 'pending',
          createdAt: '2026-09-11 10:30:00',
          updatedAt: '2026-09-11 10:30:00',
          folio: 'V-00025',
          changeDue: 20.00,
          items: [
            SaleItemModel(
              id: 1,
              saleId: 1,
              productId: 10,
              name: 'Producto A',
              quantity: 2,
              unitPrice: 50,
              total: 100,
            ),
            SaleItemModel(
              id: 2,
              saleId: 1,
              productId: 11,
              name: 'Producto B',
              quantity: 1,
              unitPrice: 50,
              total: 50,
            ),
          ],
          payments: [
            SalePaymentModel(
              id: 1,
              saleId: 1,
              method: 'Efectivo',
              amount: 170,
            ),
          ],
        );

        final ticket = TicketData.fromSale(
          sale: sale,
          config: config,
        );

        expect(ticket.empresa, 'Mi Empresa');
        expect(ticket.rfc, 'ABC123456XYZ');
        expect(ticket.direccion, 'Av. Principal 123');
        expect(ticket.telefono, '7351234567');
        expect(ticket.email, 'ventas@empresa.com');

        expect(ticket.logoPath, '/tmp/logo.webp');
        expect(ticket.encabezado, 'Gracias por su compra');
        expect(ticket.pie, 'Vuelva pronto');

        expect(ticket.folio, 'V-00025');
        expect(ticket.fecha, '2026-09-11 10:30:00');

        expect(ticket.items.length, 2);
        expect(ticket.items[0].name, 'Producto A');
        expect(ticket.items[0].quantity, 2);
        expect(ticket.items[0].unitPrice, 50);
        expect(ticket.items[0].total, 100);

        expect(ticket.items[1].name, 'Producto B');
        expect(ticket.items[1].quantity, 1);
        expect(ticket.items[1].unitPrice, 50);
        expect(ticket.items[1].total, 50);

        expect(ticket.payments.length, 1);
        expect(ticket.payments[0].method, 'Efectivo');
        expect(ticket.payments[0].amount, 170);

        expect(ticket.subtotal, 150);
        expect(ticket.total, 150);
        expect(ticket.cashReceived, 170);
        expect(ticket.changeDue, 20);

        expect(ticket.tieneLogo, isTrue);
        expect(ticket.tienePayments, isTrue);
        expect(ticket.tieneRecibido, isTrue);
        expect(ticket.tieneCambio, isTrue);

        expect(ticket.mostrarNombreNegocio, isTrue);
        expect(ticket.mostrarProductos, isTrue);
        expect(ticket.mostrarTotal, isTrue);
        expect(ticket.mostrarFecha, isTrue);
      },
    );

    test(
      'usa uuidLocal cuando la venta no tiene folio',
      () {
        final sale = SaleModel(
          id: 2,
          uuidLocal: 'uuid-fallback-002',
          serverId: null,
          businessDate: '2026-09-11',
          total: 50,
          syncStatus: 'pending',
          createdAt: '2026-09-11 11:00:00',
          updatedAt: '2026-09-11 11:00:00',
          folio: null,
          changeDue: null,
          items: const [],
          payments: const [],
        );

        final ticket = TicketData.fromSale(
          sale: sale,
          config: config,
        );

        expect(ticket.folio, 'uuid-fallback-002');
      },
    );

    test(
      'usa businessDate cuando createdAt está vacío',
      () {
        final sale = SaleModel(
          id: 3,
          uuidLocal: 'uuid-003',
          serverId: null,
          businessDate: '2026-09-11',
          total: 80,
          syncStatus: 'pending',
          createdAt: '',
          updatedAt: '2026-09-11 12:00:00',
          folio: 'V-00003',
          changeDue: null,
          items: const [],
          payments: const [],
        );

        final ticket = TicketData.fromSale(
          sale: sale,
          config: config,
        );

        expect(ticket.fecha, '2026-09-11');
      },
    );

    test(
      'normaliza textos vacíos como null',
      () {
        final emptyConfig = TicketConfig(
          empresa: 'Empresa',
          rfc: '   ',
          direccion: '',
          telefono: '   ',
          email: '',
          encabezado: '   ',
          pie: '',
          logoPath: '   ',
        );

        final sale = SaleModel(
          id: 4,
          uuidLocal: 'uuid-004',
          serverId: null,
          businessDate: '2026-09-11',
          total: 0,
          syncStatus: 'draft',
          createdAt: '2026-09-11',
          updatedAt: '2026-09-11',
          folio: null,
          changeDue: null,
          items: const [],
          payments: const [],
        );

        final ticket = TicketData.fromSale(
          sale: sale,
          config: emptyConfig,
        );

        expect(ticket.rfc, isNull);
        expect(ticket.direccion, isNull);
        expect(ticket.telefono, isNull);
        expect(ticket.email, isNull);
        expect(ticket.encabezado, isNull);
        expect(ticket.pie, isNull);
        expect(ticket.logoPath, isNull);

        expect(ticket.tieneLogo, isFalse);
      },
    );

    test(
      'formatea correctamente cantidades y precios',
      () {
        const item = TicketItemData(
          productId: 1,
          name: 'Producto',
          quantity: 2,
          unitPrice: 25.5,
          total: 51,
        );

        expect(item.formattedQuantity, '2');
        expect(item.formattedUnitPrice, '\$25.50');
        expect(item.formattedTotal, '\$51.00');

        const fractionalItem = TicketItemData(
          productId: 2,
          name: 'Producto por peso',
          quantity: 1.25,
          unitPrice: 80,
          total: 100,
        );

        expect(fractionalItem.formattedQuantity, '1.25');
      },
    );
  });
}