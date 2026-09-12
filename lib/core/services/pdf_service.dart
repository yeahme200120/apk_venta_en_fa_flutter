import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ticket_data.dart';
import 'ticket_renderer.dart';

class PdfService {
  const PdfService._();

  /// Genera un PDF de la venta utilizando exactamente la información
  /// normalizada por TicketData y TicketRenderer.
  static Future<Uint8List> generateSalePdf({
    required TicketData ticket,
  }) async {
    final document = TicketRenderer.render(ticket);

    final pdf = pw.Document();

    final logo = await _loadLogo(document.header.logoPath);

    final pageFormat = _pageFormat(ticket.config.paperSize);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),
        build: (context) {
          return _buildTicket(
            document: document,
            logo: logo,
            paperSize: ticket.config.paperSize,
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Genera el PDF directamente a partir de una venta normalizada.
  ///
  /// Este método queda como punto de entrada conveniente para las pantallas
  /// que ya trabajan con TicketData.
  static Future<Uint8List> generateTicketPdf({
    required TicketData ticket,
  }) {
    return generateSalePdf(ticket: ticket);
  }

  /// Guarda los bytes PDF en una ruta local.
  static Future<File> savePdf({
    required Uint8List bytes,
    required String path,
  }) async {
    final file = File(path);

    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  static PdfPageFormat _pageFormat(Object paperSize) {
    final is80mm = _is80mm(paperSize);

    final width = is80mm ? 80.0 : 58.0;

    // Altura larga para tickets térmicos.
    //
    // PdfPageFormat permite que el contenido ocupe solamente la altura
    // realmente utilizada por los widgets.
    return PdfPageFormat(
      width * PdfPageFormat.mm,
      250 * PdfPageFormat.mm,
      marginAll: 0,
    );
  }

  static pw.Widget _buildTicket({
    required TicketRenderDocument document,
    required pw.ImageProvider? logo,
    required Object paperSize,
  }) {
    final is80mm = _is80mm(paperSize);

    final fontSize = is80mm ? 8.5 : 7.5;
    final titleSize = is80mm ? 12.0 : 10.5;
    final totalSize = is80mm ? 11.0 : 10.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          document.header,
          logo,
          titleSize,
          fontSize,
        ),
        _separator(fontSize),
        _buildSaleInfo(
          document.saleInfo,
          fontSize,
        ),
        _buildProducts(
          document.products,
          fontSize,
          is80mm,
        ),
        _separator(fontSize),
        _buildTotals(
          document.totals,
          fontSize,
          totalSize,
        ),
        _buildPayments(
          document.payments,
          fontSize,
        ),
        _buildChange(
          document.change,
          fontSize,
        ),
        _buildQr(
          document.qr,
          is80mm,
        ),
        _buildFooter(
          document.footer,
          fontSize,
        ),
      ],
    );
  }

  static bool _is80mm(Object paperSize) {
    final normalized = paperSize.toString().trim().toLowerCase();

    return normalized == '80mm' ||
        normalized == '80 mm' ||
        normalized == '80' ||
        normalized.contains('80mm') ||
        normalized.contains('80 mm') ||
        normalized.contains('mm80');
  }

  static pw.Widget _buildHeader(
    TicketRenderHeader header,
    pw.ImageProvider? logo,
    double titleSize,
    double fontSize,
  ) {
    final children = <pw.Widget>[];

    if (header.mostrarLogo && logo != null) {
      children.add(
        pw.Center(
          child: pw.Container(
            constraints: const pw.BoxConstraints(
              maxHeight: 70,
              maxWidth: 180,
            ),
            child: pw.Image(
              logo,
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );

      children.add(pw.SizedBox(height: 4));
    }

    if (header.mostrarNombreNegocio &&
        header.empresa.trim().isNotEmpty) {
      children.add(
        pw.Center(
          child: pw.Text(
            header.empresa.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: titleSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (_hasText(header.rfc)) {
      children.add(
        _centeredText(
          'RFC: ${header.rfc!.trim()}',
          fontSize,
        ),
      );
    }

    if (_hasText(header.direccion)) {
      children.add(
        _centeredText(
          header.direccion!.trim(),
          fontSize,
        ),
      );
    }

    if (_hasText(header.telefono)) {
      children.add(
        _centeredText(
          'Tel: ${header.telefono!.trim()}',
          fontSize,
        ),
      );
    }

    if (_hasText(header.email)) {
      children.add(
        _centeredText(
          header.email!.trim(),
          fontSize,
        ),
      );
    }

    if (_hasText(header.encabezado)) {
      children.add(pw.SizedBox(height: 3));

      children.add(
        pw.Center(
          child: pw.Text(
            header.encabezado!.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _buildSaleInfo(
    TicketRenderSaleInfo info,
    double fontSize,
  ) {
    final rows = <pw.Widget>[];

    if (_hasText(info.folio)) {
      rows.add(
        _infoRow(
          'Folio',
          info.folio!,
          fontSize,
        ),
      );
    }

    if (_hasText(info.fecha)) {
      rows.add(
        _infoRow(
          'Fecha',
          info.fecha!,
          fontSize,
        ),
      );
    }

    if (_hasText(info.vendedor)) {
      rows.add(
        _infoRow(
          'Vendedor',
          info.vendedor!,
          fontSize,
        ),
      );
    }

    if (rows.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(
        children: rows,
      ),
    );
  }

  static pw.Widget _buildProducts(
    TicketRenderProducts products,
    double fontSize,
    bool is80mm,
  ) {
    if (!products.visible || !products.tieneProductos) {
      return pw.SizedBox();
    }

    final nameWidth = is80mm ? 1.0 : 0.90;

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5),
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Text(
                  'Producto',
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 22,
                child: pw.Text(
                  'Cant.',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 42,
                child: pw.Text(
                  'P.Unit.',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 48,
                child: pw.Text(
                  'Importe',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          ...products.items.map(
            (item) => _productRow(
              item,
              fontSize,
              nameWidth,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _productRow(
    TicketRenderProduct item,
    double fontSize,
    double nameWidth,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 5,
            child: pw.Text(
              item.name,
              maxLines: 4,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: fontSize,
              ),
            ),
          ),
          pw.SizedBox(
            width: 22,
            child: pw.Text(
              item.formattedQuantity,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: fontSize,
              ),
            ),
          ),
          pw.SizedBox(
            width: 42,
            child: pw.Text(
              item.formattedUnitPrice,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: fontSize,
              ),
            ),
          ),
          pw.SizedBox(
            width: 48,
            child: pw.Text(
              item.formattedTotal,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTotals(
    TicketRenderTotals totals,
    double fontSize,
    double totalSize,
  ) {
    final children = <pw.Widget>[];

    children.add(
      _moneyRow(
        'Subtotal',
        totals.formattedSubtotal,
        fontSize,
      ),
    );

    if (totals.mostrarTotal) {
      children.add(pw.SizedBox(height: 2));

      children.add(
        _moneyRow(
          'TOTAL',
          totals.formattedTotal,
          totalSize,
          bold: true,
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(
        children: children,
      ),
    );
  }

  static pw.Widget _buildPayments(
    TicketRenderPayments payments,
    double fontSize,
  ) {
    if (!payments.visible || !payments.tienePagos) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Forma de pago',
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          ...payments.payments.map(
            (payment) => _moneyRow(
              payment.displayMethod,
              payment.formattedAmount,
              fontSize,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildChange(
    TicketRenderChange change,
    double fontSize,
  ) {
    if (!change.visible) {
      return pw.SizedBox();
    }

    final rows = <pw.Widget>[];

    if (change.mostrarRecibido) {
      rows.add(
        _moneyRow(
          'Recibido',
          change.formattedCashReceived,
          fontSize,
        ),
      );
    }

    if (change.mostrarCambio) {
      rows.add(
        _moneyRow(
          'Cambio',
          change.formattedChangeDue,
          fontSize,
          bold: true,
        ),
      );
    }

    if (rows.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(
        children: rows,
      ),
    );
  }

  static pw.Widget _buildQr(
    TicketRenderQr? qr,
    bool is80mm,
  ) {
    if (qr == null || !qr.visible || qr.content.trim().isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(
        top: 8,
        bottom: 5,
      ),
      child: pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: qr.content.trim(),
          width: is80mm ? 115 : 95,
          height: is80mm ? 115 : 95,
        ),
      ),
    );
  }

  static pw.Widget _buildFooter(
    TicketRenderFooter footer,
    double fontSize,
  ) {
    if (!footer.visible || !_hasText(footer.text)) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Center(
        child: pw.Text(
          footer.text!.trim(),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }

  static pw.Widget _infoRow(
    String label,
    String value,
    double fontSize,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _moneyRow(
    String label,
    String value,
    double fontSize, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );

    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: style,
          ),
        ),
        pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: style,
        ),
      ],
    );
  }

  static pw.Widget _centeredText(
    String value,
    double fontSize,
  ) {
    return pw.Center(
      child: pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: fontSize,
        ),
      ),
    );
  }

  static pw.Widget _separator(double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Text(
        '--------------------------------',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: fontSize,
        ),
      ),
    );
  }

  static Future<pw.ImageProvider?> _loadLogo(
    String? path,
  ) async {
    if (!_hasText(path)) {
      return null;
    }

    try {
      final file = File(path!.trim());

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        return null;
      }

      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}