import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _socioController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _mostrarPassword = false;

  @override
  void dispose() {
    _socioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _acceder() async {
    final numeroSocio = _socioController.text.trim();
    final password = _passwordController.text;

    if (numeroSocio.isEmpty) {
      _showMessage('Ingresa tu número de socio');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Ingresa tu contraseña');
      return;
    }

    try {
      await _authService.login(
        identifier: numeroSocio,
        password: password,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceAll('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // ============================================
            // ENCABEZADO VERDE
            // ============================================
            Container(
              width: double.infinity,
              height: 95,
              color: const Color(0xFF9AC53B),
            ),

            // ============================================
            // CONTENIDO
            // ============================================
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          MediaQuery.of(context).size.height - 95,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 34),

                        // ========================================
                        // LOGO
                        // ========================================
                        SizedBox(
                          width: 100,
                          height: 75,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 34),

                        // ========================================
                        // NÚMERO DE SOCIO
                        // ========================================
                        const Text(
                          'Ingresa tu numero de socio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF222222),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7DDE8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: TextField(
                            controller: _socioController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              hintText: 'Número de socio',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  size: 16,
                                ),
                                onPressed: () {
                                  _socioController.clear();
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ========================================
                        // CONTRASEÑA
                        // ========================================
                        const Text(
                          'Ingresa tu contraseña',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF222222),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7DDE8),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: TextField(
                            controller: _passwordController,
                            obscureText: !_mostrarPassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _acceder(),
                            decoration: InputDecoration(
                              hintText: 'Contraseña',
                              hintStyle: const TextStyle(
                                fontSize: 13,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _mostrarPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _mostrarPassword =
                                        !_mostrarPassword;
                                  });
                                },
                              ),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // ========================================
                        // ¿OLVIDASTE TU CONTRASEÑA?
                        // ========================================
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () {
                              // Pendiente: recuperación de contraseña.
                            },
                            child: const Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ========================================
                        // BOTÓN ACCEDER
                        // ========================================
                        SizedBox(
                          width: 96,
                          height: 42,
                          child: ElevatedButton(
                            onPressed: _acceder,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF303030),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(4),
                              ),
                            ),
                            child: const Text(
                              'ACCEDER',
                              style: TextStyle(
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 100),

                        // ========================================
                        // REGISTRO
                        // ========================================
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF222222),
                            ),
                            children: [
                              const TextSpan(
                                text:
                                    '¿No tienes un número de socio? ',
                              ),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () {
                                    // Pendiente.
                                  },
                                  child: const Text(
                                    'Da Click\n'
                                    'aquí',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
