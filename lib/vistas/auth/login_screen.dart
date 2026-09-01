import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _socioController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final AuthService _authService = AuthService();

  bool _mostrarPassword = false;
  bool _cargando = false;

  @override
  void dispose() {
    _socioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // ACCEDER
  // ============================================================

  Future<void> _acceder() async {
    if (_cargando) {
      return;
    }

    final numeroEmpleado =
        _socioController.text.trim();

    final password =
        _passwordController.text;

    // ============================================================
    // VALIDACIONES
    // ============================================================

    if (numeroEmpleado.isEmpty) {
      _showMessage(
        'Ingresa tu número de empleado.',
      );
      return;
    }

    if (password.isEmpty) {
      _showMessage(
        'Ingresa tu contraseña.',
      );
      return;
    }

    // ============================================================
    // ACTIVAR CARGA
    // ============================================================

    setState(() {
      _cargando = true;
    });

    try {
      // ==========================================================
      // LOGIN
      // ==========================================================

      await _authService.login(
        identifier: numeroEmpleado,
        password: password,
      );

      if (!mounted) {
        return;
      }

      // ==========================================================
      // LOGIN CORRECTO
      // ==========================================================

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const HomeShell(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = error
          .toString()
          .replaceFirst(
            'Exception: ',
            '',
          )
          .trim();

      _showMessage(
        message.isEmpty
            ? 'No se pudo iniciar sesión.'
            : message,
      );
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  // ============================================================
  // MENSAJE
  // ============================================================

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // ======================================================
            // ENCABEZADO
            // ======================================================

            Container(
              width: double.infinity,
              height: 95,
              color: const Color(0xFF9AC53B),
            ),

            // ======================================================
            // CONTENIDO
            // ======================================================

            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          MediaQuery.of(context)
                                  .size
                                  .height -
                              95,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 34,
                        ),

                        // ==================================================
                        // LOGO
                        // ==================================================

                        SizedBox(
                          width: 100,
                          height: 75,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(
                          height: 34,
                        ),

                        // ==================================================
                        // NÚMERO DE EMPLEADO
                        // ==================================================

                        const Text(
                          'Ingresa tu número de empleado',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                Color(0xFF222222),
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Container(
                          width: double.infinity,
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFE7DDE8,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              2,
                            ),
                          ),
                          child: TextField(
                            controller:
                                _socioController,
                            enabled: !_cargando,
                            keyboardType:
                                TextInputType
                                    .number,
                            textInputAction:
                                TextInputAction
                                    .next,
                            decoration:
                                InputDecoration(
                              hintText:
                                  'Número de empleado',
                              hintStyle:
                                  const TextStyle(
                                fontSize: 13,
                              ),
                              suffixIcon:
                                  IconButton(
                                icon:
                                    const Icon(
                                  Icons
                                      .cancel_outlined,
                                  size: 16,
                                ),
                                onPressed:
                                    _cargando
                                        ? null
                                        : () {
                                            _socioController
                                                .clear();
                                          },
                              ),
                              border:
                                  InputBorder
                                      .none,
                              contentPadding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        // ==================================================
                        // CONTRASEÑA
                        // ==================================================

                        const Text(
                          'Ingresa tu contraseña',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                Color(0xFF222222),
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Container(
                          width: double.infinity,
                          decoration:
                              BoxDecoration(
                            color:
                                const Color(
                              0xFFE7DDE8,
                            ),
                            borderRadius:
                                BorderRadius
                                    .circular(
                              2,
                            ),
                          ),
                          child: TextField(
                            controller:
                                _passwordController,
                            enabled: !_cargando,
                            obscureText:
                                !_mostrarPassword,
                            textInputAction:
                                TextInputAction
                                    .done,
                            onSubmitted: (_) =>
                                _acceder(),
                            decoration:
                                InputDecoration(
                              hintText:
                                  'Contraseña',
                              hintStyle:
                                  const TextStyle(
                                fontSize: 13,
                              ),
                              suffixIcon:
                                  IconButton(
                                icon: Icon(
                                  _mostrarPassword
                                      ? Icons
                                          .visibility_off_outlined
                                      : Icons
                                          .visibility_outlined,
                                  size: 18,
                                ),
                                onPressed:
                                    _cargando
                                        ? null
                                        : () {
                                            setState(
                                              () {
                                                _mostrarPassword =
                                                    !_mostrarPassword;
                                              },
                                            );
                                          },
                              ),
                              border:
                                  InputBorder
                                      .none,
                              contentPadding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        // ==================================================
                        // OLVIDÉ CONTRASEÑA
                        // ==================================================

                        Align(
                          alignment:
                              Alignment
                                  .centerRight,
                          child:
                              GestureDetector(
                            onTap: _cargando
                                ? null
                                : () {
                                    // Pendiente:
                                    // recuperación de contraseña.
                                  },
                            child:
                                const Text(
                              '¿Olvidaste tu contraseña?',
                              style:
                                  TextStyle(
                                fontSize: 9,
                                color:
                                    Colors.blue,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 24,
                        ),

                        // ==================================================
                        // BOTÓN ACCEDER
                        // ==================================================

                        SizedBox(
                          width: 120,
                          height: 42,
                          child:
                              ElevatedButton(
                            onPressed:
                                _cargando
                                    ? null
                                    : _acceder,
                            style:
                                ElevatedButton
                                    .styleFrom(
                              backgroundColor:
                                  const Color(
                                0xFF303030,
                              ),
                              foregroundColor:
                                  Colors.white,
                              disabledBackgroundColor:
                                  const Color(
                                0xFF777777,
                              ),
                              disabledForegroundColor:
                                  Colors.white,
                              elevation: 0,
                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  4,
                                ),
                              ),
                            ),
                            child: _cargando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth:
                                          2,
                                      color:
                                          Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'ACCEDER',
                                    style:
                                        TextStyle(
                                      fontSize:
                                          10,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(
                          height: 100,
                        ),

                        // ==================================================
                        // REGISTRO
                        // ==================================================

                        RichText(
                          textAlign:
                              TextAlign.center,
                          text: TextSpan(
                            style:
                                const TextStyle(
                              fontSize: 9,
                              color:
                                  Color(
                                0xFF222222,
                              ),
                            ),
                            children: [
                              const TextSpan(
                                text:
                                    '¿No tienes un número de empleado? ',
                              ),
                              WidgetSpan(
                                child:
                                    GestureDetector(
                                  onTap:
                                      _cargando
                                          ? null
                                          : () {
                                              // Pendiente.
                                            },
                                  child:
                                      const Text(
                                    'Da Click\n'
                                    'aquí',
                                    textAlign:
                                        TextAlign
                                            .center,
                                    style:
                                        TextStyle(
                                      fontSize:
                                          9,
                                      color:
                                          Colors
                                              .blue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(
                          height: 28,
                        ),
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
