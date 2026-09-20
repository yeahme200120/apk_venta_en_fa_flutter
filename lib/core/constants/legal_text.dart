/// Texto legal de Términos y Condiciones y Aviso de Privacidad.
///
/// Este archivo centraliza TODO el contenido legal para que sea
/// fácil de actualizar sin tocar la UI.
///
/// Fecha de vigencia: 2026
/// Jurisdicción: Cuautla, Morelos, México
library;

class LegalText {
  LegalText._();

  /// Fecha de última actualización mostrada al usuario.
  static const String version = '19 de septiembre de 2026';

  /// Jurisdicción declarada.
  static const String jurisdiction = 'Cuautla, Morelos, México';

  /// Nombre legal del responsable.
  static const String companyName =
      'IAEH Software House — Digital Innovation & Development';

  /// Domicilio fiscal/operativo (placeholder hasta que se defina el real).
  static const String companyAddress =
      'Cuautla, Morelos, México (domicilio disponible a solicitud)';

  /// Correo de contacto para asuntos legales.
  static const String contactEmail = 'dani.rivera@desarrollos-iaeh.org';

  /// Responsables del tratamiento.
  static const String responsables =
      'Daniel Rivera Enríquez e Iván Alejandro Hernández Estrada';

  // ============================================================
  // RESUMEN CORTO (lo que se muestra en la pantalla principal)
  // ============================================================

  static const String shortSummary =
      '''
Al continuar, aceptas los Términos y Condiciones y el Aviso de Privacidad de $companyName.

Tratamos tus datos personales y los de tu empresa para:

• Operar el sistema de punto de venta (ventas, inventario, cajas).
• Generar estadísticas agregadas de tu operación.
• Sincronizar información entre tus dispositivos y nuestros servidores.
• Base para desarrollo de nuevas funcionalidades.

No compartimos tus datos con terceros sin tu consentimiento, salvo obligación legal.

Puedes ejercer tus derechos ARCO (Acceso, Rectificación, Cancelación y Oposición) escribiendo a:
$contactEmail

Vigente en $jurisdiction · $version
''';

  // ============================================================
  // TEXTO COMPLETO (lo que se muestra en el modal)
  // ============================================================

  static const String fullTerms =
      '''
TÉRMINOS Y CONDICIONES DE USO DE DATOS PERSONALES Y EMPRESARIALES
Última actualización: $version
Vigente en: $jurisdiction

═══════════════════════════════════════════════════════════════
1. IDENTIDAD DEL RESPONSABLE
═══════════════════════════════════════════════════════════════

El presente aviso tiene por objeto informar a los titulares de datos personales la identidad del responsable, las finalidades del tratamiento, así como los mecanismos para ejercer sus derechos ARCO (Acceso, Rectificación, Cancelación y Oposición), de conformidad con la legislación aplicable en el Estado de Morelos y la legislación federal vigente.

$companyName, con domicilio en $companyAddress, es el responsable del uso y protección de sus datos personales.

Responsables del tratamiento: $responsables.

Contacto legal: $contactEmail

═══════════════════════════════════════════════════════════════
2. DATOS PERSONALES QUE SE RECABAN
═══════════════════════════════════════════════════════════════

Para el cumplimiento de las finalidades descritas en el presente documento, se podrán recabar los siguientes datos personales:

2.1 Datos de identificación
• Nombre completo
• Correo electrónico
• Número telefónico
• RFC (cuando aplique)
• Razón social (para personas morales)

2.2 Datos de la empresa
• Nombre comercial
• Dirección
• Teléfono de contacto
• Información fiscal

2.3 Datos operativos del sistema
• Registros de ventas y transacciones
• Datos estadísticos agregados de operación
• Información de productos y servicios
• Movimientos de caja

No se recaban datos personales sensibles que afecten la esfera más íntima del titular, conforme a la definición legal.

═══════════════════════════════════════════════════════════════
3. FINALIDADES DEL TRATAMIENTO
═══════════════════════════════════════════════════════════════

3.1 Finalidades primarias (necesarias)

Los datos personales y empresariales serán utilizados para:

1. Operación del sistema POS: Gestión de ventas, inventario, cajas y catálogos.
2. Generación de estadísticas: Elaboración de reportes agregados sobre comportamiento de ventas, productos más vendidos, y métricas operativas.
3. Sincronización de datos: Transferencia segura de información entre dispositivos y servidores para respaldo y operación offline-first.
4. Cumplimiento legal: Atención a requerimientos de autoridades competentes conforme a la ley.

3.2 Finalidades secundarias (opcionales)

De manera adicional, y requiriendo su consentimiento, los datos podrán ser utilizados para:

1. Desarrollo de nuevos productos o funcionalidades: Uso de datos agregados y disociados como base para mejoras futuras del sistema.
2. Análisis estadístico avanzado: Generación de inteligencia de negocio a partir de datos anonimizados.
3. Investigación y desarrollo tecnológico: Estudios internos para innovación en herramientas de punto de venta.

El tratamiento para fines estadísticos se realizará con datos agregados que no permitan la identificación de personas específicas, conforme a lo previsto en la legislación de Morelos.

═══════════════════════════════════════════════════════════════
4. FUNDAMENTO LEGAL
═══════════════════════════════════════════════════════════════

El tratamiento de datos personales se realiza con fundamento en:

• Ley General de Protección de Datos Personales en Posesión de los Particulares (vigente desde marzo 2025).
• Ley de Protección de Datos Personales en Posesión de Sujetos Obligados del Estado de Morelos.
• Artículo 16 de la Constitución Política de los Estados Unidos Mexicanos (derecho a la protección de datos personales).
• Código Penal para el Estado de Morelos (delitos informáticos y protección de la intimidad).

═══════════════════════════════════════════════════════════════
5. CONSENTIMIENTO
═══════════════════════════════════════════════════════════════

El consentimiento para el tratamiento de datos personales se entenderá otorgado de forma libre, específica e informada.

Para las finalidades secundarias descritas en el apartado 3.2, se solicitará consentimiento expreso mediante firma autógrafa, electrónica o cualquier mecanismo de autenticación que se establezca.

El titular puede negar su consentimiento para finalidades secundarias sin que ello afecte la prestación del servicio principal.

═══════════════════════════════════════════════════════════════
6. TRANSFERENCIA DE DATOS
═══════════════════════════════════════════════════════════════

Los datos personales y empresariales no serán transferidos a terceros sin el consentimiento previo del titular, salvo en los siguientes casos previstos por la ley:

1. Cuando una ley así lo disponga.
2. Cuando exista orden judicial o mandato de autoridad competente.
3. Para el reconocimiento o defensa de derechos del titular.
4. Cuando la información sea requerida para fines estadísticos, científicos o de interés general, siempre que los datos sean agregados y no puedan relacionarse con las personas a las que se refieran.

═══════════════════════════════════════════════════════════════
7. MEDIDAS DE SEGURIDAD
═══════════════════════════════════════════════════════════════

Se implementan medidas técnicas y administrativas para proteger los datos personales contra daño, pérdida, alteración, destrucción o acceso no autorizado, incluyendo:

• Cifrado de datos en tránsito y en reposo.
• Control de acceso basado en roles.
• Auditoría de accesos y operaciones.
• Respaldo periódico de información.
• Capacitación del personal en protección de datos.

═══════════════════════════════════════════════════════════════
8. CONSERVACIÓN DE DATOS
═══════════════════════════════════════════════════════════════

Los datos personales serán conservados únicamente durante el tiempo necesario para cumplir con las finalidades descritas y conforme a los plazos legales aplicables. Una vez cumplida la finalidad, los datos serán bloqueados y posteriormente cancelados.

═══════════════════════════════════════════════════════════════
9. DERECHOS ARCO
═══════════════════════════════════════════════════════════════

El titular o su representante legal podrán ejercer en todo momento los derechos de:

• Acceso: Conocer qué datos personales se tienen y para qué se utilizan.
• Rectificación: Solicitar corrección de datos inexactos o incompletos.
• Cancelación: Solicitar la eliminación de datos cuando ya no sean necesarios.
• Oposición: Oponerse al tratamiento de datos para fines específicos.

Para ejercer estos derechos, el titular deberá presentar solicitud por escrito a través del correo electrónico: $contactEmail

═══════════════════════════════════════════════════════════════
10. USO DE DATOS PARA DESARROLLO FUTURO
═══════════════════════════════════════════════════════════════

Los datos agregados y disociados podrán ser utilizados como base para:

1. Mejoras del sistema: Optimización de funcionalidades existentes.
2. Nuevos desarrollos: Creación de herramientas complementarias.
3. Análisis de tendencias: Estudios de comportamiento de mercado.

En todos los casos, los datos serán tratados de forma que no permitan la identificación de personas físicas o morales específicas, cumpliendo con los principios de proporcionalidad y finalidad.

═══════════════════════════════════════════════════════════════
11. CAMBIOS AL AVISO
═══════════════════════════════════════════════════════════════

Cualquier modificación al presente aviso será notificada a través de los canales oficiales del responsable y publicada en la aplicación móvil.

═══════════════════════════════════════════════════════════════
12. AUTORIDAD GARANTE
═══════════════════════════════════════════════════════════════

Para asuntos relacionados con la protección de datos personales en posesión de particulares, la autoridad competente es la Secretaría Anticorrupción y Buen Gobierno, en sustitución del extinto INAI.

═══════════════════════════════════════════════════════════════
13. ACEPTACIÓN
═══════════════════════════════════════════════════════════════

El uso del sistema implica la lectura y aceptación de los presentes términos. Si no está de acuerdo con alguna disposición, deberá abstenerse de utilizar el servicio.

$companyName
$jurisdiction
$version
''';
}
