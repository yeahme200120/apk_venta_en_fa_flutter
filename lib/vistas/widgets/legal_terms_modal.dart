import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/legal_text.dart';
import '../../core/services/legal_service.dart';

/// Modal para ver los Términos y Condiciones o el Aviso de Privacidad.
///
/// Carga el contenido desde:
///   - Caché local (SharedPreferences) — si existe.
///   - Servidor (cabosync.desarrollos-iaeh.org) — si hay red.
///
/// Si el documento viene como HTML (empieza por `<!DOCTYPE html>` o
/// `<html>`), se renderiza con un WebView. Si viene como texto plano
/// o Markdown, se muestra con `SelectableText`.
///
/// Uso:
/// ```dart
/// await LegalTermsModal.open(context);         // Términos
/// await LegalTermsModal.openPrivacy(context);  // Aviso de Privacidad
/// ```
///
/// NO es una pantalla de aceptación. La aceptación vive en el
/// checkbox de RegisterScreen, que es el punto de consentimiento.
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

class _LegalSheet extends StatefulWidget {
  const _LegalSheet({required this.kind});

  /// 'terminos' | 'aviso'
  final String kind;

  @override
  State<_LegalSheet> createState() => _LegalSheetState();
}

class _LegalSheetState extends State<_LegalSheet> {
  final LegalService _service = LegalService();

  LegalDocument? _doc;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  /// Controlador del WebView cuando el documento es HTML.
  /// Se guarda como campo para no recrearlo en cada rebuild.
  WebViewController? _webController;

  String get _title => widget.kind == 'terminos'
      ? 'Términos y Condiciones'
      : 'Aviso de Privacidad';

  String get _url =>
      widget.kind == 'terminos' ? LegalUrls.terminos : LegalUrls.aviso;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _webController = null;
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final doc = await _service.getDocument(
        widget.kind,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      // Preparamos el WebView si el contenido es HTML.
      _webController = _buildWebControllerIfHtml(doc.content);

      setState(() {
        _doc = doc;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  // ============================================================
  // DETECCIÓN Y PREPARACIÓN DE HTML
  // ============================================================

  bool _isHtml(String content) {
    final trimmed = content.trimLeft().toLowerCase();
    return trimmed.startsWith('<!doctype html') ||
        trimmed.startsWith('<html') ||
        trimmed.startsWith('<body');
  }

  WebViewController? _buildWebControllerIfHtml(String content) {
    if (!_isHtml(content)) return null;

    // Envolvemos el HTML del servidor con un pequeño CSS para
    // que el viewport se ajuste bien en móvil.
    final wrapped = _wrapHtmlForMobile(content);

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Cualquier navegación interna sale al navegador externo.
            final url = request.url;
            if (url.startsWith('http://') || url.startsWith('https://')) {
              launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.dataFromString(
          wrapped,
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8'),
        ),
      );

    return controller;
  }

  String _wrapHtmlForMobile(String inner) {
    // Si el documento YA es un HTML completo, no lo envolvemos:
    // solo inyectamos el meta viewport si no lo tiene.
    final trimmed = inner.trimLeft().toLowerCase();
    final isFullDocument =
        trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html');

    if (isFullDocument) {
      if (inner.contains('name="viewport"')) {
        return inner;
      }

      // Insertamos el meta viewport dentro del <head>.
      final headIndex = inner.toLowerCase().indexOf('<head>');
      if (headIndex >= 0) {
        final insertAt = headIndex + '<head>'.length;
        return '${inner.substring(0, insertAt)}'
            '<meta name="viewport" '
            'content="width=device-width, initial-scale=1.0, '
            'maximum-scale=1.0, user-scalable=no">'
            '${inner.substring(insertAt)}';
      }

      return inner;
    }

    // Fragmento HTML: lo envolvemos.
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body { margin: 0; padding: 0; background: #ffffff; }
    body { padding: 16px; -webkit-text-size-adjust: 100%; }
    img { max-width: 100%; height: auto; }
    pre, code { white-space: pre-wrap; word-break: break-word; }
    table { max-width: 100%; }
  </style>
</head>
<body>
$inner
</body>
</html>
''';
  }

  // ============================================================
  // ABRIR EN NAVEGADOR
  // ============================================================

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_url);

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el navegador.')),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
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
                    tooltip: 'Abrir en navegador',
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.open_in_new, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Refrescar',
                    onPressed:
                        _refreshing ? null : () => _load(forceRefresh: true),
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Vigente en ${LegalText.jurisdiction} · '
                      'Versión ${_doc?.version ?? LegalText.version}'
                      '${_doc?.fromCache == true ? ' · caché local' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(child: _buildBody(scrollController)),
          ],
        );
      },
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && (_doc == null || _doc!.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
            TextButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir en navegador'),
            ),
          ],
        ),
      );
    }

    // Si el contenido es HTML, usar WebView.
    final controller = _webController;
    if (controller != null) {
      return WebViewWidget(controller: controller);
    }

    // Si no, texto plano / Markdown con SelectableText.
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: SelectableText(
        _doc?.content ?? '',
        style: const TextStyle(
          fontSize: 13,
          height: 1.55,
          color: Color(0xFF303030),
        ),
      ),
    );
  }
}