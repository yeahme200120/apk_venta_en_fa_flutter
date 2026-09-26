import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// URLs oficiales del contenido legal.
class LegalUrls {
  LegalUrls._();

  static const String base =
      'https://cabosync.desarrollos-iaeh.org/id_software_house_legal';

  static const String terminos = '$base/terminos';
  static const String aviso = '$base/aviso';
}

/// Modal para ver los Términos y Condiciones o el Aviso de Privacidad.
///
/// NO renderiza el contenido: muestra un hipervínculo a la URL
/// oficial y un botón para abrirla en el navegador.
///
/// Uso:
/// ```dart
/// await LegalTermsModal.open(context);         // Términos
/// await LegalTermsModal.openPrivacy(context);  // Aviso de Privacidad
/// ```
class LegalTermsModal {
  LegalTermsModal._();

  /// Abre el modal de Términos y Condiciones.
  static Future<void> open(BuildContext context) =>
      _open(context, kind: 'terminos');

  /// Abre el modal del Aviso de Privacidad.
  static Future<void> openPrivacy(BuildContext context) =>
      _open(context, kind: 'aviso');

  static Future<void> _open(
    BuildContext context, {
    required String kind,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LegalSheet(kind: kind),
    );
  }
}

/// Widget interno del modal.
class _LegalSheet extends StatefulWidget {
  const _LegalSheet({required this.kind});

  /// 'terminos' | 'aviso'
  final String kind;

  @override
  State<_LegalSheet> createState() => _LegalSheetState();
}

class _LegalSheetState extends State<_LegalSheet> {
  /// Reconocedor del tap sobre la URL (para Text.rich).
  late final TapGestureRecognizer _urlRecognizer;

  String get _title => widget.kind == 'terminos'
      ? 'Términos y Condiciones'
      : 'Aviso de Privacidad';

  String get _url =>
      widget.kind == 'terminos' ? LegalUrls.terminos : LegalUrls.aviso;

  String get _descripcion => widget.kind == 'terminos'
      ? 'Consulta los Términos y Condiciones completos en el siguiente enlace:'
      : 'Consulta el Aviso de Privacidad completo en el siguiente enlace:';

  @override
  void initState() {
    super.initState();
    _urlRecognizer = TapGestureRecognizer()..onTap = _openInBrowser;
  }

  @override
  void dispose() {
    _urlRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_url);

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle superior
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            // Header con título y botón cerrar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF303030),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Contenido
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _descripcion,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: Color(0xFF303030),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 👇 Hipervínculo con Text.rich (link inline)
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF303030),
                        ),
                        children: [
                          const TextSpan(text: 'Documento oficial: '),
                          TextSpan(
                            text: _url,
                            style: const TextStyle(
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.blue,
                            ),
                            recognizer: _urlRecognizer,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Botón grande para abrir en navegador
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openInBrowser,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir en navegador'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Pie con jurisdicción
                    Text(
                      'Vigente en Cuautla, Morelos, México',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}