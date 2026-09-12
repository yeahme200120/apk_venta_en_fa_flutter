import '../models/ticket_data.dart';

/// ============================================================
/// RENDERER COMÚN DEL TICKET
/// ============================================================
///
/// Punto 19:
///
/// TicketData
///     ↓
/// TicketRenderer
///     ↓
/// TicketRenderDocument
///
/// Este renderer NO genera Widgets.
/// Este renderer NO genera bytes ESC/POS.
/// Este renderer NO genera PDF.
///
/// Su responsabilidad es convertir TicketData en una
/// representación común y agnóstica del contenido del ticket.
///
/// Los distintos destinos (Preview, Bluetooth, PDF, Share,
/// Reprint) consumirán este mismo modelo.
/// ============================================================

class TicketRenderer {
  const TicketRenderer._();

  /// Construye la representación normalizada del ticket.
  static TicketRenderDocument render(
    TicketData ticket,
  ) {
    return TicketRenderDocument(
      header: _buildHeader(ticket),
      saleInfo: _buildSaleInfo(ticket),
      products: _buildProducts(ticket),
      totals: _buildTotals(ticket),
      payments: _buildPayments(ticket),
      change: _buildChange(ticket),
      qr: _buildQr(ticket),
      footer: _buildFooter(ticket),
    );
  }

  static TicketRenderHeader _buildHeader(
    TicketData ticket,
  ) {
    return TicketRenderHeader(
      mostrarLogo: ticket.tieneLogo,
      logoPath: ticket.logoPath,
      mostrarNombreNegocio: ticket.mostrarNombreNegocio,
      empresa: ticket.empresa,
      rfc: ticket.rfc,
      direccion: ticket.config.mostrarDireccion
          ? ticket.direccion
          : null,
      telefono: ticket.config.mostrarTelefono
          ? ticket.telefono
          : null,
      email: ticket.config.mostrarEmail
          ? ticket.email
          : null,
      encabezado: _hasText(ticket.encabezado)
          ? ticket.encabezado
          : 'NOTA DE VENTA',
    );
  }

  static TicketRenderSaleInfo _buildSaleInfo(
    TicketData ticket,
  ) {
    return TicketRenderSaleInfo(
      folio: ticket.config.mostrarFolio &&
              ticket.folio.isNotEmpty
          ? ticket.folio
          : null,
      fecha: ticket.mostrarFecha &&
              ticket.fecha.isNotEmpty
          ? ticket.fecha
          : null,
      vendedor: ticket.config.mostrarVendedor &&
              _hasText(ticket.vendedor)
          ? ticket.vendedor
          : null,
    );
  }

  static TicketRenderProducts _buildProducts(
    TicketData ticket,
  ) {
    if (!ticket.mostrarProductos) {
      return const TicketRenderProducts(
        visible: false,
        items: [],
      );
    }

    return TicketRenderProducts(
      visible: true,
      items: List<TicketRenderProduct>.unmodifiable(
        ticket.items.map(
          (item) => TicketRenderProduct(
            productId: item.productId,
            name: item.name,
            quantity: item.quantity,
            formattedQuantity: item.formattedQuantity,
            unitPrice: item.unitPrice,
            formattedUnitPrice: item.formattedUnitPrice,
            total: item.total,
            formattedTotal: item.formattedTotal,
          ),
        ),
      ),
    );
  }

  static TicketRenderTotals _buildTotals(
    TicketData ticket,
  ) {
    return TicketRenderTotals(
      subtotal: ticket.subtotal,
      total: ticket.total,
      mostrarTotal: ticket.mostrarTotal,
    );
  }

  static TicketRenderPayments _buildPayments(
    TicketData ticket,
  ) {
    if (!ticket.config.mostrarMetodoPago ||
        ticket.payments.isEmpty) {
      return const TicketRenderPayments(
        visible: false,
        payments: [],
      );
    }

    return TicketRenderPayments(
      visible: true,
      payments: List<TicketRenderPayment>.unmodifiable(
        ticket.payments.map(
          (payment) => TicketRenderPayment(
            method: payment.method,
            displayMethod: paymentDisplayName(
              payment.method,
            ),
            amount: payment.amount,
            formattedAmount: payment.formattedAmount,
          ),
        ),
      ),
    );
  }

  static TicketRenderChange _buildChange(
    TicketData ticket,
  ) {
    final visible = ticket.config.mostrarCambio &&
        (ticket.tieneRecibido || ticket.tieneCambio);

    return TicketRenderChange(
      visible: visible,
      cashReceived: ticket.cashReceived,
      changeDue: ticket.changeDue,
      mostrarRecibido: ticket.tieneRecibido,
      mostrarCambio: ticket.tieneCambio,
    );
  }

  static TicketRenderQr? _buildQr(
    TicketData ticket,
  ) {
    if (!ticket.tieneQr ||
        ticket.qrContenido == null) {
      return null;
    }

    return TicketRenderQr(
      visible: true,
      content: ticket.qrContenido!,
    );
  }

  static TicketRenderFooter _buildFooter(
    TicketData ticket,
  ) {
    return TicketRenderFooter(
      visible: _hasText(ticket.pie),
      text: ticket.pie,
    );
  }

  /// Convierte el método interno de pago en el texto mostrado
  /// por el ticket.
  static String paymentDisplayName(
    String method,
  ) {
    final normalized = method.trim();

    if (normalized.isEmpty) {
      return 'Pago';
    }

    switch (normalized.toLowerCase()) {
      case 'cash':
      case 'efectivo':
        return 'Efectivo';

      case 'card':
      case 'tarjeta':
        return 'Tarjeta';

      case 'credit':
      case 'credito':
      case 'crédito':
        return 'Crédito';

      case 'transfer':
      case 'transferencia':
        return 'Transferencia';

      default:
        return normalized;
    }
  }

  static String formatMoney(
    double value,
  ) {
    return '\$${value.toStringAsFixed(2)}';
  }

  static bool _hasText(
    String? value,
  ) {
    return value != null &&
        value.trim().isNotEmpty;
  }
}

/// ============================================================
/// DOCUMENTO COMÚN DEL TICKET
/// ============================================================

class TicketRenderDocument {
  const TicketRenderDocument({
    required this.header,
    required this.saleInfo,
    required this.products,
    required this.totals,
    required this.payments,
    required this.change,
    required this.qr,
    required this.footer,
  });

  final TicketRenderHeader header;
  final TicketRenderSaleInfo saleInfo;
  final TicketRenderProducts products;
  final TicketRenderTotals totals;
  final TicketRenderPayments payments;
  final TicketRenderChange change;
  final TicketRenderQr? qr;
  final TicketRenderFooter footer;
}

/// ============================================================
/// ENCABEZADO
/// ============================================================

class TicketRenderHeader {
  const TicketRenderHeader({
    required this.mostrarLogo,
    required this.logoPath,
    required this.mostrarNombreNegocio,
    required this.empresa,
    required this.rfc,
    required this.direccion,
    required this.telefono,
    required this.email,
    required this.encabezado,
  });

  final bool mostrarLogo;
  final String? logoPath;

  final bool mostrarNombreNegocio;
  final String empresa;

  final String? rfc;
  final String? direccion;
  final String? telefono;
  final String? email;

  final String? encabezado;
}

/// ============================================================
/// INFORMACIÓN DE LA VENTA
/// ============================================================

class TicketRenderSaleInfo {
  const TicketRenderSaleInfo({
    required this.folio,
    required this.fecha,
    required this.vendedor,
  });

  final String? folio;
  final String? fecha;
  final String? vendedor;
}

/// ============================================================
/// PRODUCTOS
/// ============================================================

class TicketRenderProducts {
  const TicketRenderProducts({
    required this.visible,
    required this.items,
  });

  final bool visible;
  final List<TicketRenderProduct> items;

  bool get tieneProductos => items.isNotEmpty;
}

class TicketRenderProduct {
  const TicketRenderProduct({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.formattedQuantity,
    required this.unitPrice,
    required this.formattedUnitPrice,
    required this.total,
    required this.formattedTotal,
  });

  final int productId;
  final String name;

  final double quantity;
  final String formattedQuantity;

  final double unitPrice;
  final String formattedUnitPrice;

  final double total;
  final String formattedTotal;
}

/// ============================================================
/// TOTALES
/// ============================================================

class TicketRenderTotals {
  const TicketRenderTotals({
    required this.subtotal,
    required this.total,
    required this.mostrarTotal,
  });

  final double subtotal;
  final double total;
  final bool mostrarTotal;

  String get formattedSubtotal {
    return TicketRenderer.formatMoney(subtotal);
  }

  String get formattedTotal {
    return TicketRenderer.formatMoney(total);
  }
}

/// ============================================================
/// PAGOS
/// ============================================================

class TicketRenderPayments {
  const TicketRenderPayments({
    required this.visible,
    required this.payments,
  });

  final bool visible;
  final List<TicketRenderPayment> payments;

  bool get tienePagos => payments.isNotEmpty;
}

class TicketRenderPayment {
  const TicketRenderPayment({
    required this.method,
    required this.displayMethod,
    required this.amount,
    required this.formattedAmount,
  });

  final String method;
  final String displayMethod;

  final double amount;
  final String formattedAmount;
}

/// ============================================================
/// RECIBIDO / CAMBIO
/// ============================================================

class TicketRenderChange {
  const TicketRenderChange({
    required this.visible,
    required this.cashReceived,
    required this.changeDue,
    required this.mostrarRecibido,
    required this.mostrarCambio,
  });

  final bool visible;

  final double cashReceived;
  final double changeDue;

  final bool mostrarRecibido;
  final bool mostrarCambio;

  String get formattedCashReceived {
    return TicketRenderer.formatMoney(
      cashReceived,
    );
  }

  String get formattedChangeDue {
    return TicketRenderer.formatMoney(
      changeDue,
    );
  }
}

/// ============================================================
/// QR
/// ============================================================

class TicketRenderQr {
  const TicketRenderQr({
    required this.visible,
    required this.content,
  });

  final bool visible;
  final String content;
}

/// ============================================================
/// PIE
/// ============================================================

class TicketRenderFooter {
  const TicketRenderFooter({
    required this.visible,
    required this.text,
  });

  final bool visible;
  final String? text;
}