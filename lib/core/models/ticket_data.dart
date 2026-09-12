import '../models/sale_model.dart';
import '../services/printer_service.dart';

/// ============================================================
/// DATOS NORMALIZADOS DEL TICKET
/// ============================================================
///
/// Punto 17:
/// SaleModel + TicketConfig
///        ↓
///    TicketData
///
/// Este modelo NO imprime, NO genera PDF y NO depende de
/// Bluetooth. Su responsabilidad es representar el contenido
/// normalizado del ticket.
///
/// Posteriormente será consumido por TicketRenderer.
/// ============================================================

class TicketData {
  const TicketData({
    required this.config,
    required this.empresa,
    required this.rfc,
    required this.direccion,
    required this.telefono,
    required this.email,
    required this.logoPath,
    required this.encabezado,
    required this.pie,
    required this.folio,
    required this.fecha,
    required this.vendedor,
    required this.items,
    required this.payments,
    required this.subtotal,
    required this.total,
    required this.cashReceived,
    required this.changeDue,
  });

  final TicketConfig config;

  final String empresa;
  final String? rfc;
  final String? direccion;
  final String? telefono;
  final String? email;
  final String? logoPath;

  final String? encabezado;
  final String? pie;

  final String folio;
  final String fecha;
  final String? vendedor;

  final List<TicketItemData> items;
  final List<TicketPaymentData> payments;

  final double subtotal;
  final double total;

  final double cashReceived;
  final double changeDue;

  /// Construye los datos del ticket a partir de una venta real.
  factory TicketData.fromSale({
    required SaleModel sale,
    required TicketConfig config,
  }) {
    final items = sale.items
        .map(
          (item) => TicketItemData(
            productId: item.productId,
            name: item.name,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            total: item.total,
          ),
        )
        .toList(growable: false);

    final payments = sale.payments
        .map(
          (payment) => TicketPaymentData(
            method: payment.method,
            amount: payment.amount,
          ),
        )
        .toList(growable: false);

    final subtotal = items.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );

    final cashReceived = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    final folio = _firstNonEmpty([
      sale.folio,
      sale.uuidLocal,
    ]);

    final fecha = _firstNonEmpty([
      sale.createdAt,
      sale.businessDate,
    ]);

    return TicketData(
      config: config,
      empresa: config.empresa,
      rfc: _nullable(config.rfc),
      direccion: _nullable(config.direccion),
      telefono: _nullable(config.telefono),
      email: _nullable(config.email),
      logoPath: _nullable(config.logoPath),
      encabezado: _nullable(config.encabezado),
      pie: _nullable(config.pie),
      folio: folio,
      fecha: fecha,
      // SaleModel actualmente no contiene vendedor.
      vendedor: null,
      items: items,
      payments: payments,
      subtotal: subtotal,
      total: sale.total,
      cashReceived: cashReceived,
      changeDue: sale.changeDue ?? 0,
    );
  }

  bool get mostrarNombreNegocio {
    return config.campos['nombre_negocio'] ?? true;
  }

  bool get mostrarProductos {
    return config.campos['productos'] ?? true;
  }

  bool get mostrarTotal {
    return config.campos['total'] ?? true;
  }

  bool get mostrarFecha {
    return config.campos['fecha'] ?? config.mostrarFecha;
  }

  bool get tieneLogo {
    return config.mostrarLogo &&
        logoPath != null &&
        logoPath!.trim().isNotEmpty;
  }

  bool get tienePayments => payments.isNotEmpty;

  bool get tieneCambio => changeDue > 0;

  bool get tieneRecibido => cashReceived > 0;

  bool get tieneQr {
    return config.mostrarQr &&
        config.qrContenido != null &&
        config.qrContenido!.trim().isNotEmpty;
  }

  String? get qrContenido {
    if (!tieneQr) {
      return null;
    }

    return config.qrContenido!.trim();
  }

  static String _firstNonEmpty(
    List<String?> values,
  ) {
    for (final value in values) {
      if (value == null) {
        continue;
      }

      final normalized = value.trim();

      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return '';
  }

  static String? _nullable(
    String? value,
  ) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();

    return normalized.isEmpty
        ? null
        : normalized;
  }
}

/// ============================================================
/// PRODUCTO DEL TICKET
/// ============================================================

class TicketItemData {
  const TicketItemData({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final int productId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double total;

  String get formattedQuantity {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }

    return quantity.toStringAsFixed(2);
  }

  String get formattedUnitPrice {
    return '\$${unitPrice.toStringAsFixed(2)}';
  }

  String get formattedTotal {
    return '\$${total.toStringAsFixed(2)}';
  }
}

/// ============================================================
/// PAGO DEL TICKET
/// ============================================================

class TicketPaymentData {
  const TicketPaymentData({
    required this.method,
    required this.amount,
  });

  final String method;
  final double amount;

  String get formattedAmount {
    return '\$${amount.toStringAsFixed(2)}';
  }
}