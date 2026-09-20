import 'package:flutter/material.dart';

import '../../core/constants/legal_text.dart';

/// Utilidad para abrir los términos y condiciones como modal.
///
/// Uso:
/// ```dart
/// await LegalTermsModal.open(context);
/// ```
///
/// Se usa desde RegisterScreen → link "Ver términos completos".
///
/// NO es una pantalla de aceptación. La aceptación vive en el
/// checkbox de RegisterScreen, que es el punto de consentimiento.
class LegalTermsModal {
  LegalTermsModal._();

  /// Abre el modal con los términos completos.
  static Future<void> open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
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
                      const Expanded(
                        child: Text(
                          'Términos y Condiciones',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF303030),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Cerrar',
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
                          '${LegalText.version}',
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
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    child: SelectableText(
                      LegalText.fullTerms,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: Color(0xFF303030),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}