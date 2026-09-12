import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class WhatsAppService {
  const WhatsAppService._();

  /// Comparte un PDF utilizando el selector nativo de Android.
  ///
  /// WhatsApp aparecerá como destino cuando esté instalado.
  /// No se realiza ningún envío automático ni se utiliza una API
  /// no oficial de WhatsApp.
  static Future<bool> sharePdf({
    required List<int> bytes,
    required String fileName,
    String? text,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('El PDF generado está vacío.');
    }

    final normalizedFileName = _normalizeFileName(fileName);

    final directory = await getTemporaryDirectory();

    final file = File(
      '${directory.path}/$normalizedFileName',
    );

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    try {
      final result = await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType: 'application/pdf',
            name: normalizedFileName,
          ),
        ],
        text: text,
        subject: normalizedFileName,
      );

      return result.status != ShareResultStatus.unavailable;
    } finally {
      // El archivo se mantiene durante la operación de compartir.
      //
      // No se elimina inmediatamente porque Android puede necesitar
      // terminar de leer el URI compartido después de cerrar el
      // selector de aplicaciones.
    }
  }

  static String _normalizeFileName(String fileName) {
    var value = fileName.trim();

    if (value.isEmpty) {
      value = 'ticket.pdf';
    }

    if (!value.toLowerCase().endsWith('.pdf')) {
      value = '$value.pdf';
    }

    return value.replaceAll(
      RegExp(r'[\\/:*?"<>|]'),
      '_',
    );
  }
}