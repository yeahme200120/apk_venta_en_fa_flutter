import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

// ✅ NUEVO: modal reutilizable de términos
import '../legal/terms_screen.dart';

import '../../core/services/auth_service.dart';
// 🆕 UBICACIÓN
import '../../core/services/location_service.dart';
// ✅ NUEVO: para guardar el consentimiento por usuario
import '../../core/storage/app_storage.dart';
import '../../core/constants/legal_text.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ============================================================
  // CONTROLADORES
  // ============================================================

  final TextEditingController _empresaNombreController =
      TextEditingController();
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _rfcController = TextEditingController();

  final AuthService _authService = AuthService();

  // ============================================================
  // ESTADO
  // ============================================================

  bool _cargando = false;
  bool _aceptaTerminos = false;

  String? _errorEmpresaNombre;
  String? _errorNombre;
  String? _errorEmail;
  String? _errorTerminos;
  String? _errorGeneral;

  @override
  void dispose() {
    _empresaNombreController.dispose();
    _nombreController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _rfcController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDACIONES LOCALES
  // ============================================================

  bool _esEmailValido(String value) {
    final email = value.trim();
    if (email.isEmpty) return false;

    final regex = RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$');
    return regex.hasMatch(email);
  }

  void _limpiarErrores() {
    setState(() {
      _errorEmpresaNombre = null;
      _errorNombre = null;
      _errorEmail = null;
      _errorTerminos = null;
      _errorGeneral = null;
    });
  }

  // ============================================================
  // IDENTIFICADOR DEL DISPOSITIVO
  // ============================================================

  Future<String?> _deviceIdentifier() async {
    try {
      final plugin = DeviceInfoPlugin();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await plugin.androidInfo;
        return androidInfo.id;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await plugin.iosInfo;
        return iosInfo.identifierForVendor ?? iosInfo.name;
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ No se pudo obtener el identificador del dispositivo: $e');
      return null;
    }
  }

  // ============================================================
  // REGISTRAR
  // ============================================================

  Future<void> _registrar() async {
    if (_cargando) return;

    _limpiarErrores();

    // ----------------------------------------------------------
    // VALIDACIONES LOCALES
    // ----------------------------------------------------------

    final empresaNombre = _empresaNombreController.text.trim();
    final nombre = _nombreController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final telefono = _telefonoController.text.trim();
    final rfc = _rfcController.text.trim();

    bool hayError = false;

    if (empresaNombre.isEmpty) {
      setState(() => _errorEmpresaNombre = 'Ingresa el nombre del negocio.');
      hayError = true;
    }

    if (nombre.isEmpty) {
      setState(() => _errorNombre = 'Ingresa tu nombre.');
      hayError = true;
    }

    if (email.isEmpty) {
      setState(() => _errorEmail = 'Ingresa tu correo.');
      hayError = true;
    } else if (!_esEmailValido(email)) {
      setState(() => _errorEmail = 'El correo no tiene un formato válido.');
      hayError = true;
    }

    if (!_aceptaTerminos) {
      setState(() {
        _errorTerminos =
            'Debes aceptar los términos y condiciones para continuar.';
      });
      hayError = true;
    }

    if (hayError) {
      // Feedback adicional para el caso de términos.
      if (_errorTerminos != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Debes aceptar los términos y condiciones para continuar.',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // ----------------------------------------------------------
    // VERIFICAR INTERNET
    // ----------------------------------------------------------

    final tieneInternet = await InternetConnection().hasInternetAccess;

    if (!tieneInternet) {
      if (!mounted) return;

      setState(() {
        _errorGeneral = 'Necesitas conexión a Internet para crear tu cuenta.';
      });
      return;
    }

    // ----------------------------------------------------------
    // OBTENER MAC
    // ----------------------------------------------------------

    final mac = await _deviceIdentifier();

    if (mac == null || mac.trim().isEmpty) {
      if (!mounted) return;

      setState(() {
        _errorGeneral =
            'No se pudo identificar este dispositivo. '
            'Contacta a soporte.';
      });
      return;
    }

    // ----------------------------------------------------------
    // 🆕 UBICACIÓN (OPCIONAL)
    // ----------------------------------------------------------

    final location = await LocationService().getCurrentLocation();

    // ----------------------------------------------------------
    // LLAMAR AL BACKEND
    // ----------------------------------------------------------

    setState(() => _cargando = true);

    try {
      final payload = await _authService.register(
        empresaNombre: empresaNombre,
        nombre: nombre,
        email: email,
        macAddress: mac,
        telefono: telefono.isEmpty ? null : telefono,
        rfc: rfc.isEmpty ? null : rfc,
        latitude: location?.latitude,
        longitude: location?.longitude,
        accuracy: location?.accuracy,
        locationProvider: location?.provider,
        // ✅ T&C OBLIGATORIOS
        terminosAceptados: _aceptaTerminos, // ya validaste que sea true arriba
        terminosVersion: LegalText.version, // '2026-09-19' según el modal
      );

      if (!mounted) return;

      // ============================================================
      // ✅ FIX: guardar el consentimiento de T&C POR USUARIO.
      // ============================================================
      //
      // El backend ya creó al usuario y devolvió sus datos en
      // `payload['user']`. Extraemos el id y guardamos el flag
      // `terms_accepted_user_{userId} = true` para auditoría.
      //
      // Si por algún motivo el userId no viene en la respuesta,
      // no bloqueamos el registro: el usuario lo verá en el
      // próximo login si decides agregar la verificación allí.

      final userIdRaw = payload['user']?['id'];
      final userId = userIdRaw is num
          ? userIdRaw.toInt()
          : int.tryParse('$userIdRaw') ?? 0;

      if (userId > 0) {
        await AppStorage().markTermsAccepted(userId);
        debugPrint('✅ T&C aceptados guardados para userId=$userId');
      } else {
        debugPrint(
          '⚠️ No se pudo obtener userId del payload para guardar T&C.',
        );
      }

      if (!mounted) return;

      // --------------------------------------------------------
      // MOSTRAR CREDENCIALES INICIALES
      // --------------------------------------------------------

      await _mostrarDialogoCredenciales(payload);

      if (!mounted) return;

      // El usuario ya quedó logueado (AuthService.saveOnlineSession).
      // Devolvemos true para que LoginScreen navegue al POS.
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      final raw = error.toString().replaceFirst('Exception: ', '').trim();
      final rawLower = raw.toLowerCase();

      if (rawLower.contains('correo') ||
          rawLower.contains('email') ||
          rawLower.contains('email_exists')) {
        setState(
          () => _errorEmail = raw.isEmpty
              ? 'Este correo ya está registrado.'
              : raw,
        );
      } else if (rawLower.contains('empresa')) {
        setState(
          () => _errorEmpresaNombre = raw.isEmpty
              ? 'Esta empresa ya está registrada.'
              : raw,
        );
      } else if (rawLower.contains('mac') || rawLower.contains('dispositivo')) {
        setState(
          () => _errorGeneral = raw.isEmpty
              ? 'Este dispositivo ya creó una cuenta.'
              : raw,
        );
      } else if (rawLower.contains('rate') || rawLower.contains('demasiados')) {
        setState(
          () => _errorGeneral = raw.isEmpty
              ? 'Demasiados intentos. Intenta más tarde.'
              : raw,
        );
      } else {
        setState(
          () => _errorGeneral = raw.isEmpty
              ? 'No se pudo completar el registro.'
              : raw,
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ============================================================
  // ABRIR TÉRMINOS COMPLETOS
  // ============================================================

  Future<void> _abrirTerminosCompletos() async {
    await LegalTermsModal.open(context);
  }

  // ============================================================
  // DIÁLOGO DE CREDENCIALES INICIALES
  // ============================================================

  Future<void> _mostrarDialogoCredenciales(Map<String, dynamic> payload) async {
    final credenciales = payload['credenciales_iniciales'] is Map
        ? Map<String, dynamic>.from(payload['credenciales_iniciales'] as Map)
        : <String, dynamic>{};

    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : <String, dynamic>{};

    final numeroUsuario =
        credenciales['numero_usuario']?.toString() ??
        user['numero_usuario']?.toString() ??
        '—';

    final passwordGenerica =
        credenciales['password_generica']?.toString() ?? '—';

    final mensaje =
        credenciales['mensaje']?.toString() ??
        'Esta es tu contraseña temporal. '
            'Cópiala en un lugar seguro. '
            'Debes cambiarla desde Configuración → Usuario.';

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text('Cuenta creada', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guarda estas credenciales en un lugar seguro. '
                  'Las necesitarás para iniciar sesión.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                _CredencialRow(
                  label: 'Número de usuario',
                  value: numeroUsuario,
                ),
                const SizedBox(height: 10),
                _CredencialRow(
                  label: 'Contraseña temporal',
                  value: passwordGenerica,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade800,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mensaje,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF303030),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Crear cuenta',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // TÍTULO
              // ==================================================
              const Text(
                'Prueba 7 días gratis',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF303030),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Crea tu cuenta y empieza a vender en minutos.',
                style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
              ),
              const SizedBox(height: 24),

              // ==================================================
              // NOMBRE DEL NEGOCIO
              // ==================================================
              const _FieldLabel('Nombre del negocio *'),
              const SizedBox(height: 6),
              _InputField(
                controller: _empresaNombreController,
                enabled: !_cargando,
                hintText: 'Ej. Mi Cafetería',
                textInputAction: TextInputAction.next,
                errorText: _errorEmpresaNombre,
                onChanged: (_) {
                  if (_errorEmpresaNombre != null) {
                    setState(() => _errorEmpresaNombre = null);
                  }
                },
              ),
              const SizedBox(height: 18),

              // ==================================================
              // TU NOMBRE
              // ==================================================
              const _FieldLabel('Tu nombre *'),
              const SizedBox(height: 6),
              _InputField(
                controller: _nombreController,
                enabled: !_cargando,
                hintText: 'Ej. Juan Pérez',
                textInputAction: TextInputAction.next,
                errorText: _errorNombre,
                onChanged: (_) {
                  if (_errorNombre != null) {
                    setState(() => _errorNombre = null);
                  }
                },
              ),
              const SizedBox(height: 18),

              // ==================================================
              // CORREO
              // ==================================================
              const _FieldLabel('Correo *'),
              const SizedBox(height: 6),
              _InputField(
                controller: _emailController,
                enabled: !_cargando,
                hintText: 'tucorreo@ejemplo.com',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                errorText: _errorEmail,
                onChanged: (_) {
                  if (_errorEmail != null) {
                    setState(() => _errorEmail = null);
                  }
                },
              ),
              const SizedBox(height: 18),

              // ==================================================
              // TELÉFONO (OPCIONAL)
              // ==================================================
              const _FieldLabel('Teléfono (opcional)'),
              const SizedBox(height: 6),
              _InputField(
                controller: _telefonoController,
                enabled: !_cargando,
                hintText: '555 123 4567',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 18),

              // ==================================================
              // RFC (OPCIONAL)
              // ==================================================
              const _FieldLabel('RFC (opcional)'),
              const SizedBox(height: 6),
              _InputField(
                controller: _rfcController,
                enabled: !_cargando,
                hintText: 'XAXX010101000',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 18),

              // ==================================================
              // ✅ TÉRMINOS Y CONDICIONES (checkbox + link)
              // ==================================================
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _aceptaTerminos
                      ? const Color(0xFFE8F5E9)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _errorTerminos != null
                        ? Colors.red.shade400
                        : _aceptaTerminos
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFE0E0E0),
                    width: _errorTerminos != null || _aceptaTerminos ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _aceptaTerminos,
                            onChanged: _cargando
                                ? null
                                : (value) {
                                    setState(() {
                                      _aceptaTerminos = value ?? false;
                                      if (_aceptaTerminos) {
                                        _errorTerminos = null;
                                      }
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: _cargando
                                ? null
                                : () => setState(
                                    () => _aceptaTerminos = !_aceptaTerminos,
                                  ),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Text(
                                'He leído y acepto los Términos y Condiciones '
                                'y el Aviso de Privacidad.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF444444),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _cargando ? null : _abrirTerminosCompletos,
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text(
                          'Ver términos completos',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorTerminos != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _errorTerminos!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ==================================================
              // ERROR GENERAL
              // ==================================================
              if (_errorGeneral != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorGeneral!,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ==================================================
              // BOTÓN CREAR CUENTA
              // ==================================================
              Center(
                child: FractionallySizedBox(
                  widthFactor: 0.85,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _cargando ? null : _registrar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF303030),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF777777),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: _cargando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'CREAR CUENTA',
                              style: TextStyle(fontSize: 13, letterSpacing: 1),
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ==================================================
              // VOLVER AL LOGIN
              // ==================================================
              Center(
                child: TextButton(
                  onPressed: _cargando
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Ya tengo cuenta, iniciar sesión',
                    style: TextStyle(fontSize: 13, color: Colors.blue),
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGETS REUTILIZABLES
// ============================================================

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: Color(0xFF444444)),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.enabled,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFE7DDE8),
            borderRadius: BorderRadius.circular(4),
            border: errorText != null
                ? Border.all(color: Colors.red.shade400, width: 1.2)
                : null,
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 13,
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
      ],
    );
  }
}

class _CredencialRow extends StatelessWidget {
  const _CredencialRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF303030),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
