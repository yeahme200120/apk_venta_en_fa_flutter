import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/sale_model.dart';
import '../../core/models/ticket_data.dart';
import '../../core/services/printer_service.dart';
import '../../core/services/ticket_renderer.dart';

class TicketPreviewScreen extends StatelessWidget {
  const TicketPreviewScreen({
    super.key,
    required this.sale,
    required this.config,
  });

  final SaleModel sale;
  final TicketConfig config;

  @override
  Widget build(BuildContext context) {
    final ticket = TicketData.fromSale(sale: sale, config: config);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Vista previa del ticket'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _TicketPaper(ticket: ticket),
          ),
        ),
      ),
    );
  }
}

class _TicketPaper extends StatelessWidget {
  const _TicketPaper({required this.ticket});

  final TicketData ticket;

  TicketRenderDocument get render {
    return TicketRenderer.render(ticket);
  }

  double get _paperWidth {
    if (ticket.config.paperSize == PaperSize.mm80) {
      return 384;
    }

    return 300;
  }

  TextAlign get _alignment {
    switch (ticket.config.alineacion.toLowerCase()) {
      case 'centro':
      case 'center':
      case 'centrado':
        return TextAlign.center;

      case 'derecha':
      case 'right':
        return TextAlign.right;

      case 'izquierda':
      case 'left':
      default:
        return TextAlign.left;
    }
  }

  double get _baseFontSize {
    final value = ticket.config.tamanoFuente.toDouble();

    return value.clamp(8.0, 30.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ticket_preview_paper'),
      width: _paperWidth,
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(0, 8),
            color: Color(0x22000000),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.black,
          fontSize: _baseFontSize,
          height: 1.25,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            const _TicketDivider(),
            const SizedBox(height: 8),
            _buildSaleInfo(),
            const SizedBox(height: 8),
            const _TicketDivider(),
            const SizedBox(height: 8),
            _buildProducts(),
            const SizedBox(height: 8),
            _buildTotals(),
            _buildPayments(),
            _buildChange(),
            _buildQr(),
            const SizedBox(height: 12),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final header = render.header;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header.mostrarLogo) _buildLogo(),

        if (header.mostrarLogo) const SizedBox(height: 10),

        if (header.mostrarNombreNegocio)
          Text(
            header.empresa,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _baseFontSize + 4,
              fontWeight: FontWeight.bold,
            ),
          ),

        if (_hasText(header.rfc))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('RFC: ${header.rfc}', textAlign: TextAlign.center),
          ),

        if (_hasText(header.direccion))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(header.direccion!, textAlign: TextAlign.center),
          ),

        if (_hasText(header.telefono))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Tel: ${header.telefono}', textAlign: TextAlign.center),
          ),

        if (_hasText(header.email))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(header.email!, textAlign: TextAlign.center),
          ),

        if (_hasText(header.encabezado))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              header.encabezado!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildLogo() {
    final path = render.header.logoPath;

    if (path == null || path.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180, maxHeight: 90),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaleInfo() {
    final saleInfo = render.saleInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasText(saleInfo.folio))
          _InfoRow(label: 'Folio', value: saleInfo.folio!, boldValue: true),

        if (_hasText(saleInfo.fecha))
          _InfoRow(label: 'Fecha', value: saleInfo.fecha!),

        if (_hasText(saleInfo.vendedor))
          _InfoRow(label: 'Vendedor', value: saleInfo.vendedor!),
      ],
    );
  }

  Widget _buildProducts() {
    final products = render.products;

    if (!products.visible) {
      return const SizedBox.shrink();
    }

    if (!products.tieneProductos) {
      return Text('Sin productos', textAlign: _alignment);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProductHeader(),
        const SizedBox(height: 6),
        ...products.items.map(
          (item) => _ProductRow(item: item, fontSize: _baseFontSize),
        ),
      ],
    );
  }

  Widget _buildTotals() {
    final totals = render.totals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const _TicketDivider(),
        const SizedBox(height: 8),
        _MoneyRow(label: 'Subtotal', value: totals.subtotal),
        if (totals.mostrarTotal)
          _MoneyRow(
            label: 'TOTAL',
            value: totals.total,
            bold: true,
            fontSize: _baseFontSize + 2,
          ),
      ],
    );
  }

  Widget _buildPayments() {
    final payments = render.payments;

    if (!payments.visible || !payments.tienePagos) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'FORMA DE PAGO',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          ...payments.payments.map(
            (payment) =>
                _MoneyRow(label: payment.displayMethod, value: payment.amount),
          ),
        ],
      ),
    );
  }

  Widget _buildChange() {
    final change = render.change;

    if (!change.visible) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (change.mostrarRecibido)
            _MoneyRow(label: 'RECIBIDO', value: change.cashReceived),

          if (change.mostrarCambio)
            _MoneyRow(label: 'CAMBIO', value: change.changeDue, bold: true),
        ],
      ),
    );
  }

  Widget _buildQr() {
    final qr = render.qr;

    if (qr == null || !qr.visible) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          const Text(
            'Código QR',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          QrImageView(
            data: qr.content,
            version: QrVersions.auto,
            size: ticket.config.paperSize == PaperSize.mm80 ? 180 : 150,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(8),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final footer = render.footer;

    if (!footer.visible || !_hasText(footer.text)) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(footer.text!, textAlign: TextAlign.center),
        const SizedBox(height: 18),
      ],
    );
  }

  bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.item, required this.fontSize});

  final TicketRenderProduct item;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  item.formattedQuantity,
                  textAlign: TextAlign.left,
                  style: TextStyle(fontSize: fontSize - 1),
                ),
              ),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: fontSize),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.formattedTotal,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: fontSize),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Text(
              '${item.formattedQuantity} x ${item.formattedUnitPrice}',
              style: TextStyle(fontSize: fontSize - 2, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 34,
          child: Text('CANT', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Text(
            'PRODUCTO',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          width: 75,
          child: Text(
            'TOTAL',
            textAlign: TextAlign.right,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.boldValue = false,
  });

  final String label;
  final String value;
  final bool boldValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.fontSize,
  });

  final String label;
  final double value;
  final bool bold;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            '\$${value.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: style,
          ),
        ],
      ),
    );
  }
}

class _TicketDivider extends StatelessWidget {
  const _TicketDivider();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '--------------------------------',
      maxLines: 1,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.black54),
    );
  }
}