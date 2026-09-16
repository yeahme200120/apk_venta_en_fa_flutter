import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final ApiClient _apiClient = ApiClient();

  bool _enviando = false;
  bool _enviado = false;
  String? _errorEmail;
  String? _errorGeneral;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ============================================================
  // ENVIAR
  // ============================================================

  Future<void> _enviar() async {
    if (_enviando) return;

    final email = _emailController.text.trim();

    setState(() {
      _errorEmail = null;
      _errorGeneral = null;
    });

    if (email.isEmpty) {
      setState(() => _errorEmail = 'Ingresa tu correo electrónico.');
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorEmail = 'Ingresa un correo electrónico válido.');
      return;
    }

    setState(() => _enviando = true);

    try {
      await _apiClient.forgotPassword(email: email);

      if (!mounted) return;
      setState(() => _enviado = true);
    } on DioException catch (e) {
      if (!mounted) return;

      final status = e.response?.statusCode;
      final payload = e.response?.data;

      // 404 EMAIL_NOT_FOUND → mostramos mensaje neutral (seguridad).
      if (status == 404) {
        setState(() => _enviado = true);
        return;
      }

      // 500 MAIL_ERROR → el servidor no pudo enviar el correo.
      if (status == 500) {
        setState(() {
          _errorGeneral = ApiClient.parseApiError(
            payload,
            fallback: 'No fue posible enviar el correo. Intenta más tarde.',
          );
        });
        return;
      }

      // 429 RATE LIMIT
      if (status == 429) {
        setState(() {
          _errorGeneral = ApiClient.parseApiError(
            payload,
            fallback: 'Demasiados intentos. Intenta más tarde.',
          );
        });
        return;
      }

      setState(() {
        _errorGeneral = ApiClient.parseApiError(
          payload,
          fallback: 'No se pudo procesar la solicitud.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorGeneral =
            'No se pudo conectar con el servidor. Revisa tu conexión.';
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
          'Recuperar contraseña',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: _enviado ? _buildConfirmacion() : _buildFormulario(),
        ),
      ),
    );
  }

  // ============================================================
  // FORMULARIO
  // ============================================================

  Widget _buildFormulario() {
    return Column(
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
          'Ingresa tu correo registrado',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          'Te enviaremos un enlace para restablecer tu contraseña. '
          'Ábrelo desde tu correo en cualquier dispositivo.',
          style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
        ),

        const SizedBox(height: 28),

        const Text(
          'Correo electrónico',
          style: TextStyle(fontSize: 13, color: Color(0xFF444444)),
        ),

        const SizedBox(height: 6),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE7DDE8),
            borderRadius: BorderRadius.circular(4),
            border: _errorEmail != null
                ? Border.all(color: Colors.red.shade400, width: 1.2)
                : null,
          ),
          child: TextField(
            controller: _emailController,
            enabled: !_enviando,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _enviar(),
            onChanged: (_) {
              if (_errorEmail != null) setState(() => _errorEmail = null);
            },
            decoration: const InputDecoration(
              hintText: 'correo@ejemplo.com',
              hintStyle: TextStyle(fontSize: 13),
              prefixIcon: Icon(Icons.email_outlined, size: 20),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            ),
          ),
        ),

        if (_errorEmail != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _errorEmail!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),

        if (_errorGeneral != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    'Enviar instrucciones',
                    style: TextStyle(fontSize: 13, letterSpacing: 0.5),
                  ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CONFIRMACIÓN
  // ============================================================

  Widget _buildConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),

        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF9AC53B).withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            size: 42,
            color: Color(0xFF58751F),
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Revisa tu bandeja de entrada',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF222222),
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          'Si el correo que ingresaste está registrado, '
          'recibirás un enlace para restablecer tu contraseña. '
          'Ábrelo en tu navegador y sigue las instrucciones.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
        ),

        const SizedBox(height: 36),

        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF303030),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              'Volver al inicio de sesión',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}