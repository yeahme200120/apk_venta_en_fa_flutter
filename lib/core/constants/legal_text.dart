/// Metadatos legales. El contenido completo se descarga desde:
///   - https://cabosync.desarrollos-iaeh.org/id_software_house_legal/terminos
///   - https://cabosync.desarrollos-iaeh.org/id_software_house_legal/aviso
///
/// y se cachea localmente con `LegalService`.
library;

class LegalText {
  LegalText._();

  static const String version = '25 de septiembre de 2026';

  static const String jurisdiction = 'Cuautla, Morelos, México';

  static const String companyName = 'ID SOFTWARE HOUSE';

  static const String contactEmail = 'dani.rivera@desarrollos-iaeh.org';

  static const String shortSummary = '''
Al continuar, aceptas los Términos y Condiciones y el Aviso de Privacidad de $companyName.

Tratamos tus datos personales y los de tu empresa para operar el sistema de punto de venta, generar estadísticas agregadas, sincronizar información y desarrollar nuevas funcionalidades.

No compartimos tus datos con terceros sin tu consentimiento, salvo obligación legal.

Puedes ejercer tus derechos ARCO escribiendo a:
$contactEmail

Vigente en $jurisdiction · $version
''';
}