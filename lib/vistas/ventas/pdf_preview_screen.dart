import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/models/sale_model.dart';
import '../../core/models/ticket_data.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/printer_service.dart';

class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.sale,
  });

  final SaleModel sale;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final PrinterService _printerService = PrinterService();

  late final Future<Uint8List> _pdfFuture;

  @override
  void initState() {
    super.initState();

    _pdfFuture = _generatePdf();
  }

  Future<Uint8List> _generatePdf() async {
    final config = await _printerService.loadTicketConfig();

    final ticket = TicketData.fromSale(
      sale: widget.sale,
      config: config,
    );

    return PdfService.generateSalePdf(
      ticket: ticket,
    );
  }

  String get _fileName {
    final folio = widget.sale.folio?.trim();

    if (folio != null && folio.isNotEmpty) {
      return 'ticket_$folio.pdf';
    }

    final localId = widget.sale.uuidLocal.trim();

    if (localId.isNotEmpty) {
      return 'ticket_$localId.pdf';
    }

    return 'ticket.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista previa PDF'),
      ),
      body: PdfPreview(
        build: (_) => _pdfFuture,
        pdfFileName: _fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: false,
        allowSharing: true,
        maxPageWidth: 420,
      ),
    );
  }
}