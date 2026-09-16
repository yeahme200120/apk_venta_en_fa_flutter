import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.token,
    required this.email,
  });

  final String token;
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();
  final ApiClient _apiClient = ApiClient();

  bool _mostrarPassword = false;
  bool _mostrarPasswordConfirm = false;
  bool _enviando = false;

  String? _errorPassword;
  String? _errorPasswordConfirm;
  String? _errorGeneral;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDACIÓN LOCAL
  // ============================================================

  String? _validarPassword(String value) {
    if (value.isEmpty) {
      return 'Ingresa una contraseña.';
    }

    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres.';
    }

    final tieneMayuscula = value.contains(RegExp(r'[A-Z]'));
    final tieneMinuscula = value.contains(RegExp(r'[a-z]'));
    final tieneNumero = value.contains(RegExp(r'[0-9]'));

    if (!tieneMayuscula || !tieneMinuscula || !tieneNumero) {
      return 'Debe incluir mayúscula, minúscula y número.';
    }

    return null;
  }

  // ============================================================
  // ENVIAR
  // ============================================================

  Future<void> _enviar() async {
    if (_enviando) return;

    setState(() {
      _errorPassword = null;
      _errorPasswordConfirm = null;
      _errorGeneral = null;
    });

    final password = _passwordController.text;
    final passwordConfirm = _passwordConfirmController.text;

    final passwordError = _validarPassword(password);

    if (passwordError != null) {
      setState(() => _errorPassword = passwordError);
      return;
    }

    if (passwordConfirm.isEmpty) {
      setState(() => _errorPasswordConfirm = 'Confirma tu contraseña.');
      return;
    }

    if (password != passwordConfirm) {
      setState(() => _errorPasswordConfirm = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() => _enviando = true);

    try {
      await _apiClient.resetPassword(
        email: widget.email,
        token: widget.token,
        password: password,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contraseña actualizada',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'Ya puedes iniciar sesión con tu nueva contraseña.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      // Volvemos al login.
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      final raw = error.toString().replaceFirst('Exception: ', '').trim();

      setState(() {
        _errorGeneral = raw.isEmpty
            ? 'No se pudo restablecer la contraseña. Intenta más tarde.'
            : raw;
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF303030),
        title: const Text(
          'Nueva contraseña',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF9AC53B).withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_outlined,
                    size: 38,
                    color: Color(0xFF58751F),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Define tu nueva contraseña',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Correo: ${widget.email}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF666666),
                ),
              ),

              const SizedBox(height: 28),

              // ----------------------------------------------
              // NUEVA CONTRASEÑA
              // ----------------------------------------------
              const Text(
                'Nueva contraseña',
                style: TextStyle(fontSize: 13, color: Color(0xFF444444)),
              ),

              const SizedBox(height: 6),

              _PasswordField(
                controller: _passwordController,
                enabled: !_enviando,
                hintText: 'Mín. 8 caracteres',
                obscureText: !_mostrarPassword,
                errorText: _errorPassword,
                onToggleVisibility: () => setState(
                  () => _mostrarPassword = !_mostrarPassword,
                ),
                onChanged: (_) {
                  if (_errorPassword != null) {
                    setState(() => _errorPassword = null);
                  }
                },
              ),

              const SizedBox(height: 6),
              const Text(
                'Debe incluir mayúscula, minúscula y número.',
                style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
              ),

              const SizedBox(height: 20),

              // ----------------------------------------------
              // CONFIRMAR
              // ----------------------------------------------
              const Text(
                'Confirmar contraseña',
                style: TextStyle(fontSize: 13, color: Color(0xFF444444)),
              ),

              const SizedBox(height: 6),

              _PasswordField(
                controller: _passwordConfirmController,
                enabled: !_enviando,
                hintText: 'Repite la contraseña',
                obscureText: !_mostrarPasswordConfirm,
                errorText: _errorPasswordConfirm,
                onToggleVisibility: () => setState(
                  () => _mostrarPasswordConfirm = !_mostrarPasswordConfirm,
                ),
                onChanged: (_) {
                  if (_errorPasswordConfirm != null) {
                    setState(() => _errorPasswordConfirm = null);
                  }
                },
              ),

              if (_errorGeneral != null) ...[
                const SizedBox(height: 12),
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
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _enviando ? null : _enviar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF303030),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF777777),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Restablecer contraseña',
                          style: TextStyle(fontSize: 13, letterSpacing: 0.5),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CAMPO DE CONTRASEÑA
// ============================================================

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.enabled,
    required this.hintText,
    required this.obscureText,
    required this.onToggleVisibility,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hintText;
  final bool obscureText;
  final VoidCallback onToggleVisibility;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
            obscureText: obscureText,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(fontSize: 13),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: enabled ? onToggleVisibility : null,
              ),
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