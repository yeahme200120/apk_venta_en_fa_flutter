import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/ticket_data.dart';
import 'ticket_renderer.dart';
import 'printer_service.dart';

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

  // ============================================================
  // PDF DE MOVIMIENTO DE CAJA
  // ============================================================
  //
  // Genera un PDF de una sola hoja con la misma estética que el
  // ticket de venta.
  //
  // Parámetros:
  //   • movement: Map con los datos del movimiento:
  //       - tipo          (String)  ingreso | egreso | retiro | ajuste
  //       - concepto      (String)
  //       - monto         (double)
  //       - referencia    (String?)
  //       - notas         (String?)
  //       - forma_pago    (String?)
  //       - registrado_at (String ISO8601)
  //       - usuario       (String?)
  //       - folio         (String?)
  //       - fecha_comercial (String)  YYYY-MM-DD
  //       - caja_nombre   (String?)
  //   • config: TicketConfig ya cargado (empresa, logo, colores).
  //
  // NO crea dependencias nuevas. Reutiliza:
  //   - _loadLogo
  //   - _pageFormat
  //   - _separator
  //   - _moneyRow
  //   - _centeredText
  //   - _hasText

  static Future<Uint8List> generateCashMovementPdf({
    required Map<String, dynamic> movement,
    required TicketConfig config,
  }) async {
    final pdf = pw.Document();

    final logo = await _loadLogo(config.logoPath);

    final pageFormat = _pageFormat(config.paperSize);

    final is80mm = _is80mm(config.paperSize);

    final fontSize = is80mm ? 8.5 : 7.5;
    final titleSize = is80mm ? 12.0 : 10.5;
    final totalSize = is80mm ? 11.0 : 10.0;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _movementHeader(
                config: config,
                logo: logo,
                titleSize: titleSize,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _movementTitle(
                movement: movement,
                fontSize: titleSize,
              ),
              _movementInfo(
                movement: movement,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _movementConcept(
                movement: movement,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _movementTotal(
                movement: movement,
                fontSize: totalSize,
              ),
              _movementFooter(
                config: config,
                fontSize: fontSize,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ============================================================
  // PDF DE RESUMEN DE CAJA (por secciones)
  // ============================================================
  //
  // Genera un PDF del resumen completo de la caja del día:
  //
  //   1. Encabezado (empresa, logo, RFC, dirección) — usa la
  //      MISMA configuración de ticket global.
  //   2. Datos de la caja (apertura, cierre, estado, fecha
  //      comercial).
  //   3. Ventas del día por método de pago.
  //   4. Movimientos manuales por tipo y método.
  //   5. Resumen (ingresos, egresos, ajustes, neto).
  //
  // No depende de TicketData: recibe los mapas crudos tal como
  // los devuelve LocalDb / CashService.
  static Future<Uint8List> generateCashSummaryPdf({
    required Map<String, dynamic>? caja,
    required Map<String, dynamic> resumen,
    required List<Map<String, dynamic>> ventasPorMetodo,
    required List<Map<String, dynamic>> movimientosPorTipoMetodo,
    required TicketConfig config,
    required String fechaComercial,
  }) async {
    final pdf = pw.Document();

    final logo = await _loadLogo(config.logoPath);

    final pageFormat = _pageFormat(config.paperSize);

    final is80mm = _is80mm(config.paperSize);

    final fontSize = is80mm ? 8.5 : 7.5;
    final titleSize = is80mm ? 12.0 : 10.5;
    final totalSize = is80mm ? 11.0 : 10.0;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _summaryHeader(
                config: config,
                logo: logo,
                titleSize: titleSize,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _summaryTitle(titleSize),
              _summaryBoxInfo(
                caja: caja,
                fechaComercial: fechaComercial,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _summarySectionVentas(
                ventasPorMetodo: ventasPorMetodo,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _summarySectionMovimientos(
                movimientosPorTipoMetodo: movimientosPorTipoMetodo,
                fontSize: fontSize,
              ),
              _separator(fontSize),
              _summarySectionResumen(
                resumen: resumen,
                fontSize: fontSize,
                totalSize: totalSize,
              ),
              _summaryFooter(
                config: config,
                fontSize: fontSize,
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ============================================================
  // HELPERS INTERNOS DEL PDF DE MOVIMIENTO
  // ============================================================

  static pw.Widget _movementHeader({
    required TicketConfig config,
    required pw.ImageProvider? logo,
    required double titleSize,
    required double fontSize,
  }) {
    final children = <pw.Widget>[];

    if (config.mostrarLogo && logo != null) {
      children.add(
        pw.Center(
          child: pw.Container(
            constraints: const pw.BoxConstraints(
              maxHeight: 70,
              maxWidth: 180,
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        ),
      );

      children.add(pw.SizedBox(height: 4));
    }

    final mostrarNombre = config.campos['nombre_negocio'] ?? true;

    if (mostrarNombre && config.empresa.trim().isNotEmpty) {
      children.add(
        pw.Center(
          child: pw.Text(
            config.empresa.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: titleSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (_hasText(config.rfc)) {
      children.add(_centeredText('RFC: ${config.rfc!.trim()}', fontSize));
    }

    if (config.mostrarDireccion && _hasText(config.direccion)) {
      children.add(_centeredText(config.direccion!.trim(), fontSize));
    }

    if (config.mostrarTelefono && _hasText(config.telefono)) {
      children.add(_centeredText('Tel: ${config.telefono!.trim()}', fontSize));
    }

    if (config.mostrarEmail && _hasText(config.email)) {
      children.add(_centeredText(config.email!.trim(), fontSize));
    }

    if (_hasText(config.encabezado)) {
      children.add(pw.SizedBox(height: 3));

      children.add(
        pw.Center(
          child: pw.Text(
            config.encabezado!.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _movementTitle({
    required Map<String, dynamic> movement,
    required double fontSize,
  }) {
    final tipo = movement['tipo']?.toString().toLowerCase().trim() ?? '';

    final label = switch (tipo) {
      'ingreso' => 'INGRESO',
      'egreso' => 'EGRESO',
      'retiro' => 'RETIRO',
      'ajuste' => 'AJUSTE',
      _ => tipo.toUpperCase(),
    };

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Center(
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static pw.Widget _movementInfo({
    required Map<String, dynamic> movement,
    required double fontSize,
  }) {
    final rows = <pw.Widget>[];

    final folio = movement['folio']?.toString().trim() ?? '';
    if (folio.isNotEmpty) {
      rows.add(_infoRow('Folio', folio, fontSize));
    }

    final fecha = movement['registrado_at']?.toString().trim() ??
        movement['fecha']?.toString().trim() ??
        '';
    if (fecha.isNotEmpty) {
      rows.add(_infoRow('Fecha', _formatMovementDate(fecha), fontSize));
    }

    final usuario = movement['usuario']?.toString().trim() ?? '';
    if (usuario.isNotEmpty) {
      rows.add(_infoRow('Usuario', usuario, fontSize));
    }

    final caja = movement['caja_nombre']?.toString().trim() ?? '';
    if (caja.isNotEmpty) {
      rows.add(_infoRow('Caja', caja, fontSize));
    }

    final fechaComercial =
        movement['fecha_comercial']?.toString().trim() ?? '';
    if (fechaComercial.isNotEmpty) {
      rows.add(_infoRow('Fecha comercial', fechaComercial, fontSize));
    }

    if (rows.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(children: rows),
    );
  }

  static pw.Widget _movementConcept({
    required Map<String, dynamic> movement,
    required double fontSize,
  }) {
    final children = <pw.Widget>[];

    final concepto = movement['concepto']?.toString().trim() ?? '';
    if (concepto.isNotEmpty) {
      children.add(
        pw.Text(
          'Concepto',
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

      children.add(pw.SizedBox(height: 2));

      children.add(
        pw.Text(
          concepto,
          style: pw.TextStyle(fontSize: fontSize),
        ),
      );
    }

    final referencia = movement['referencia']?.toString().trim() ?? '';
    if (referencia.isNotEmpty) {
      children.add(pw.SizedBox(height: 4));

      children.add(
        _infoRow('Referencia', referencia, fontSize),
      );
    }

    final formaPago = movement['forma_pago']?.toString().trim() ?? '';
    if (formaPago.isNotEmpty) {
      children.add(
        _infoRow('Forma de pago', formaPago, fontSize),
      );
    }

    final notas = movement['notas']?.toString().trim() ?? '';
    if (notas.isNotEmpty) {
      children.add(pw.SizedBox(height: 4));

      children.add(
        pw.Text(
          'Notas',
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

      children.add(pw.SizedBox(height: 2));

      children.add(
        pw.Text(
          notas,
          style: pw.TextStyle(fontSize: fontSize),
        ),
      );
    }

    if (children.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  static pw.Widget _movementTotal({
    required Map<String, dynamic> movement,
    required double fontSize,
  }) {
    final monto = _toDouble(movement['monto']);

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: _moneyRow(
        'MONTO',
        _money(monto),
        fontSize,
        bold: true,
      ),
    );
  }

  static pw.Widget _movementFooter({
    required TicketConfig config,
    required double fontSize,
  }) {
    final pie = config.pie?.trim() ?? '';

    if (pie.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Center(
        child: pw.Text(
          pie,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: fontSize),
        ),
      ),
    );
  }

  static String _formatMovementDate(String value) {
    final parsed = DateTime.tryParse(value);

    if (parsed == null) return value;

    final local = parsed.toLocal();

    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '') ?? '') ?? 0;
  }

  static String _money(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }

  // ============================================================
  // HELPERS INTERNOS DEL PDF DE RESUMEN DE CAJA
  // ============================================================

  static pw.Widget _summaryHeader({
    required TicketConfig config,
    required pw.ImageProvider? logo,
    required double titleSize,
    required double fontSize,
  }) {
    final children = <pw.Widget>[];

    if (config.mostrarLogo && logo != null) {
      children.add(
        pw.Center(
          child: pw.Container(
            constraints: const pw.BoxConstraints(
              maxHeight: 70,
              maxWidth: 180,
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        ),
      );
      children.add(pw.SizedBox(height: 4));
    }

    final mostrarNombre = config.campos['nombre_negocio'] ?? true;

    if (mostrarNombre && config.empresa.trim().isNotEmpty) {
      children.add(
        pw.Center(
          child: pw.Text(
            config.empresa.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: titleSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );
    }

    if (_hasText(config.rfc)) {
      children.add(_centeredText('RFC: ${config.rfc!.trim()}', fontSize));
    }

    if (config.mostrarDireccion && _hasText(config.direccion)) {
      children.add(_centeredText(config.direccion!.trim(), fontSize));
    }

    if (config.mostrarTelefono && _hasText(config.telefono)) {
      children.add(_centeredText('Tel: ${config.telefono!.trim()}', fontSize));
    }

    if (config.mostrarEmail && _hasText(config.email)) {
      children.add(_centeredText(config.email!.trim(), fontSize));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _summaryTitle(double fontSize) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Center(
        child: pw.Text(
          'RESUMEN DE CAJA',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static pw.Widget _summaryBoxInfo({
    required Map<String, dynamic>? caja,
    required String fechaComercial,
    required double fontSize,
  }) {
    final rows = <pw.Widget>[];

    rows.add(_infoRow('Fecha comercial', fechaComercial, fontSize));

    if (caja != null) {
      final estado = (caja['estado'] ?? '').toString();
      if (estado.isNotEmpty) {
        rows.add(_infoRow('Estado', estado.toUpperCase(), fontSize));
      }

      final montoApertura = _toDouble(caja['monto_apertura']);
      rows.add(_infoRow('Monto apertura', _money(montoApertura), fontSize));

      final abiertaAt = caja['abierta_at']?.toString();
      if (abiertaAt != null && abiertaAt.isNotEmpty) {
        rows.add(_infoRow('Apertura', _formatMovementDate(abiertaAt), fontSize));
      }

      final cerradaAt = caja['cerrada_at']?.toString();
      if (cerradaAt != null && cerradaAt.isNotEmpty) {
        rows.add(_infoRow('Cierre', _formatMovementDate(cerradaAt), fontSize));

        final declarado = _toDouble(caja['monto_declarado']);
        rows.add(_infoRow('Monto declarado', _money(declarado), fontSize));

        final diferencia = _toDouble(caja['diferencia']);
        rows.add(_infoRow('Diferencia', _money(diferencia), fontSize));
      }
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Column(children: rows),
    );
  }

  static pw.Widget _summarySectionVentas({
    required List<Map<String, dynamic>> ventasPorMetodo,
    required double fontSize,
  }) {
    final children = <pw.Widget>[];

    children.add(
      pw.Text(
        'VENTAS DEL DÍA POR MÉTODO',
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );

    children.add(pw.SizedBox(height: 3));

    if (ventasPorMetodo.isEmpty) {
      children.add(
        pw.Text(
          'Sin ventas registradas.',
          style: pw.TextStyle(fontSize: fontSize),
        ),
      );
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: children,
      );
    }

    double total = 0;

    for (final v in ventasPorMetodo) {
      final label = v['method_label']?.toString() ?? '—';
      final tickets = (v['tickets'] is num)
          ? (v['tickets'] as num).toInt()
          : int.tryParse(v['tickets']?.toString() ?? '') ?? 0;
      final monto = _toDouble(v['total']);
      total += monto;

      children.add(
        _moneyRow(
          '$label ($tickets ticket${tickets == 1 ? '' : 's'})',
          _money(monto),
          fontSize,
        ),
      );
    }

    children.add(pw.SizedBox(height: 2));

    children.add(
      _moneyRow('Total ventas', _money(total), fontSize, bold: true),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _summarySectionMovimientos({
    required List<Map<String, dynamic>> movimientosPorTipoMetodo,
    required double fontSize,
  }) {
    final children = <pw.Widget>[];

    children.add(
      pw.Text(
        'MOVIMIENTOS MANUALES',
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );

    children.add(pw.SizedBox(height: 3));

    if (movimientosPorTipoMetodo.isEmpty) {
      children.add(
        pw.Text(
          'Sin movimientos manuales.',
          style: pw.TextStyle(fontSize: fontSize),
        ),
      );
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: children,
      );
    }

    final porTipo = <String, List<Map<String, dynamic>>>{};

    for (final m in movimientosPorTipoMetodo) {
      final tipo = (m['tipo'] ?? '').toString();
      porTipo.putIfAbsent(tipo, () => []);
      porTipo[tipo]!.add(m);
    }

    const orden = ['ingreso', 'ajuste', 'egreso', 'retiro'];

    for (final tipo in orden) {
      final items = porTipo[tipo];
      if (items == null || items.isEmpty) continue;

      children.add(pw.SizedBox(height: 4));

      children.add(
        pw.Text(
          tipo.toUpperCase(),
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

      for (final m in items) {
        final label = m['method_label']?.toString() ?? '—';
        final cantidad = (m['cantidad'] is num)
            ? (m['cantidad'] as num).toInt()
            : int.tryParse(m['cantidad']?.toString() ?? '') ?? 0;
        final total = _toDouble(m['total']);

        children.add(
          _moneyRow(
            '  $label (${cantidad}x)',
            _money(total),
            fontSize,
          ),
        );
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _summarySectionResumen({
    required Map<String, dynamic> resumen,
    required double fontSize,
    required double totalSize,
  }) {
    final ingresos = _toDouble(resumen['ingresos']);
    final egresos = _toDouble(resumen['retiros_gastos']);
    final ajustes = _toDouble(resumen['ajustes']);
    final ventasEfectivo = _toDouble(resumen['ventas_efectivo']);
    final ventasTotal = _toDouble(resumen['ventas_total']);
    final neto = _toDouble(resumen['neto']);

    final children = <pw.Widget>[];

    children.add(
      pw.Text(
        'RESUMEN',
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );

    children.add(pw.SizedBox(height: 3));

    children.add(
      _moneyRow('Ventas en efectivo', _money(ventasEfectivo), fontSize),
    );

    if (ventasTotal > ventasEfectivo) {
      children.add(
        _moneyRow(
          'Ventas otros métodos',
          _money(ventasTotal - ventasEfectivo),
          fontSize,
        ),
      );
    }

    children.add(_moneyRow('Ingresos manuales', _money(ingresos), fontSize));
    children.add(_moneyRow('Retiros / gastos', _money(egresos), fontSize));

    if (ajustes != 0) {
      children.add(_moneyRow('Ajustes', _money(ajustes), fontSize));
    }

    children.add(pw.SizedBox(height: 3));

    children.add(
      _moneyRow('NETO EN CAJA', _money(neto), totalSize, bold: true),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static pw.Widget _summaryFooter({
    required TicketConfig config,
    required double fontSize,
  }) {
    final pie = config.pie?.trim() ?? '';

    if (pie.isEmpty) {
      return pw.SizedBox();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Center(
        child: pw.Text(
          pie,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: fontSize),
        ),
      ),
    );
  }
}