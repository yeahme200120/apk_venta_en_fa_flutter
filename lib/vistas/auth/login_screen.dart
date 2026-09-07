import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../home_shell.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _identificadorController =
      TextEditingController();
  final TextEditingController _passwordController =
      TextEditingController();

  final AuthService _authService = AuthService();

  bool _mostrarPassword = false;
  bool _cargando = false;

  // Errores por campo provenientes del servidor
  String? _errorIdentificador;
  String? _errorPassword;
  String? _errorGeneral;

  @override
  void dispose() {
    _identificadorController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // ACCEDER
  // ============================================================

  Future<void> _acceder() async {
    if (_cargando) return;

    final identificador = _identificadorController.text.trim();
    final password = _passwordController.text;

    // Limpiar errores previos
    setState(() {
      _errorIdentificador = null;
      _errorPassword = null;
      _errorGeneral = null;
    });

    if (identificador.isEmpty) {
      setState(() => _errorIdentificador = 'Ingresa tu número de usuario o correo.');
      return;
    }

    if (password.isEmpty) {
      setState(() => _errorPassword = 'Ingresa tu contraseña.');
      return;
    }

    setState(() => _cargando = true);

    try {
      await _authService.login(
        identifier: identificador,
        password: password,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;

      final raw = error.toString().replaceFirst('Exception: ', '').trim();

      // Intentar parsear errores de campo del servidor (422)
      // El ApiClient lanza excepciones con el texto del primer mensaje de error.
      // Si el texto corresponde a identificador o contraseña, lo asignamos al campo.
      final rawLower = raw.toLowerCase();

      if (rawLower.contains('número de usuario') ||
          rawLower.contains('correo') ||
          rawLower.contains('identificador') ||
          rawLower.contains('usuario no encontrado') ||
          rawLower.contains('inactivo') ||
          rawLower.contains('empresa')) {
        setState(() => _errorIdentificador = raw.isEmpty ? 'Número de usuario o correo incorrectos.' : raw);
      } else if (rawLower.contains('contraseña') ||
          rawLower.contains('password')) {
        setState(() => _errorPassword = raw.isEmpty ? 'Número de usuario o contraseña incorrectos.' : raw);
      } else {
        setState(() => _errorGeneral = raw.isEmpty ? 'No se pudo iniciar sesión.' : raw);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),

                // ======================================================
                // LOGO
                // ======================================================

                Center(
                  child: SizedBox(
                    width: 110,
                    height: 80,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ======================================================
                // NÚMERO DE USUARIO / CORREO
                // ======================================================

                const Text(
                  'Número de usuario o correo',
                  style: TextStyle(fontSize: 13, color: Color(0xFF444444)),
                ),

                const SizedBox(height: 6),

                _InputField(
                  controller: _identificadorController,
                  enabled: !_cargando,
                  hintText: 'Número de usuario o correo electrónico',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    onPressed: _cargando
                        ? null
                        : () {
                            _identificadorController.clear();
                            setState(() => _errorIdentificador = null);
                          },
                  ),
                  errorText: _errorIdentificador,
                  onChanged: (_) {
                    if (_errorIdentificador != null) {
                      setState(() => _errorIdentificador = null);
                    }
                  },
                ),

                const SizedBox(height: 20),

                // ======================================================
                // CONTRASEÑA
                // ======================================================

                const Text(
                  'Contraseña',
                  style: TextStyle(fontSize: 13, color: Color(0xFF444444)),
                ),

                const SizedBox(height: 6),

                _InputField(
                  controller: _passwordController,
                  enabled: !_cargando,
                  hintText: 'Contraseña',
                  obscureText: !_mostrarPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _acceder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _mostrarPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: _cargando
                        ? null
                        : () => setState(() => _mostrarPassword = !_mostrarPassword),
                  ),
                  errorText: _errorPassword,
                  onChanged: (_) {
                    if (_errorPassword != null) {
                      setState(() => _errorPassword = null);
                    }
                  },
                ),

                const SizedBox(height: 10),

                // ======================================================
                // OLVIDÉ CONTRASEÑA
                // ======================================================

                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _cargando
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            );
                          },
                    child: const Text(
                      '¿Olvidaste tu contraseña?',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),

                // ======================================================
                // ERROR GENERAL
                // ======================================================

                if (_errorGeneral != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

                // ======================================================
                // BOTÓN ACCEDER
                // ======================================================

                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.78,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _acceder,
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
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'ACCEDER',
                                style: TextStyle(fontSize: 13, letterSpacing: 1),
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 80),

                // ======================================================
                // REGISTRO
                // ======================================================

                Center(
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF444444),
                      ),
                      children: [
                        const TextSpan(text: '¿No tienes un número de usuario? '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: _cargando ? null : () {},
                            child: const Text(
                              'Da click aquí',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CAMPO DE TEXTO REUTILIZABLE
// ============================================================

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.enabled,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
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
            obscureText: obscureText,
            onSubmitted: onSubmitted,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(fontSize: 13),
              suffixIcon: suffixIcon,
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
