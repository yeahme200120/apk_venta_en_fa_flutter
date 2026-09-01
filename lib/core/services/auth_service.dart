import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient();

  /// ============================================================
  /// LOGIN
  /// ============================================================
  ///
  /// El login se considera válido únicamente cuando:
  ///
  /// 1. El identificador no está vacío.
  /// 2. La contraseña no está vacía.
  /// 3. Laravel devuelve un token.
  /// 4. Laravel devuelve un usuario válido.
  /// 5. El usuario tiene un ID válido.
  /// 6. El identificador enviado corresponde al usuario devuelto.
  ///
  /// Esto último evita que un backend mal configurado permita
  /// iniciar sesión con un número de empleado incorrecto.
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();

    // IMPORTANTE:
    // No hacemos trim() a la contraseña.
    // Los espacios podrían formar parte de una contraseña válida.
    final cleanPassword = password;

    // ============================================================
    // VALIDACIONES LOCALES
    // ============================================================

    if (cleanIdentifier.isEmpty) {
      throw Exception('Ingresa tu número de empleado.');
    }

    if (cleanPassword.isEmpty) {
      throw Exception('Ingresa tu contraseña.');
    }

    // ============================================================
    // LOGIN CONTRA EL BACKEND
    // ============================================================

    final payload = await _apiClient.login(
      identifier: cleanIdentifier,
      password: cleanPassword,
    );

    if (payload.isEmpty) {
      await AppStorage().logOut();

      throw Exception(
        'El servidor no devolvió una respuesta válida.',
      );
    }

    // ============================================================
    // TOKEN
    // ============================================================

    final dynamic rawToken =
        payload['token'] ?? payload['access_token'];

    final token = rawToken?.toString().trim() ?? '';

    if (token.isEmpty) {
      await AppStorage().logOut();

      throw Exception(
        payload['message']?.toString() ??
            'Número de empleado o contraseña incorrectos.',
      );
    }

    // ============================================================
    // USUARIO
    // ============================================================

    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(
            payload['user'] as Map,
          )
        : <String, dynamic>{};

    if (user.isEmpty) {
      await AppStorage().logOut();

      throw Exception(
        payload['message']?.toString() ??
            'El servidor no devolvió los datos del usuario.',
      );
    }

    // ============================================================
    // ID DEL USUARIO
    // ============================================================

    final userId = _parsePositiveInt(
      user['id'] ?? user['user_id'],
    );

    if (userId <= 0) {
      await AppStorage().logOut();

      throw Exception(
        'La respuesta del servidor no contiene un usuario válido.',
      );
    }

    // ============================================================
    // VALIDAR IDENTIFICADOR DEVUELTO POR EL SERVIDOR
    // ============================================================
    //
    // El backend puede utilizar distintos nombres dependiendo
    // de cómo esté construido el modelo:
    //
    // numero_usuario
    // numero_empleado
    // numero_socio
    // username
    //
    // Para este POS el login de la pantalla es por número de
    // empleado. Por eso exigimos que el número devuelto coincida.
    //

    final serverIdentifier = _extractUserIdentifier(user);

    if (serverIdentifier.isEmpty) {
      await AppStorage().logOut();

      throw Exception(
        'El servidor no devolvió el número de empleado del usuario.',
      );
    }

    if (serverIdentifier != cleanIdentifier) {
      await AppStorage().logOut();

      throw Exception(
        'El número de empleado no corresponde al usuario autenticado.',
      );
    }

    // ============================================================
    // EMPRESA
    // ============================================================

    final empresa = payload['empresa'] is Map
        ? Map<String, dynamic>.from(
            payload['empresa'] as Map,
          )
        : <String, dynamic>{};

    final empresaId = _parsePositiveInt(
      empresa['id'] ?? empresa['empresa_id'],
    );

    if (empresaId <= 0) {
      await AppStorage().logOut();

      throw Exception(
        'El usuario no tiene una empresa válida asociada.',
      );
    }

    // ============================================================
    // NOMBRE DEL USUARIO
    // ============================================================

    final userName = _extractUserName(user);

    // ============================================================
    // GUARDAR SESIÓN
    // ============================================================

    await AppStorage().saveSession(
      token: token,
      userId: userId,
      empresaId: empresaId,
      userName: userName,
      isLoggedIn: true,
    );

    // ============================================================
    // NOMBRE DE EMPRESA
    // ============================================================

    final dynamic rawCompanyName =
        empresa['nombre'] ?? empresa['name'];

    if (rawCompanyName != null) {
      final companyName = rawCompanyName.toString().trim();

      if (companyName.isNotEmpty) {
        await AppStorage().saveCompanyName(companyName);
      }
    }

    // ============================================================
    // CONFIGURACIÓN DE EMPRESA
    // ============================================================

    final configuration = empresa['configuracion'];

    if (configuration is Map) {
      final settings = Map<String, dynamic>.from(
        configuration,
      );

      await AppStorage().saveOperationState({
        'cajas_activas': settings['cajas_activas'] == true,
        'mesas_activas': settings['mesas_activas'] == true,
        'caja_abierta': null,
      });
    }

    // ============================================================
    // DEVOLVER RESPUESTA
    // ============================================================

    return payload;
  }

  // ============================================================
  // EXTRAER IDENTIFICADOR DEL USUARIO
  // ============================================================

  String _extractUserIdentifier(
    Map<String, dynamic> user,
  ) {
    final possibleValues = [
      user['numero_usuario'],
      user['numero_empleado'],
      user['numero_socio'],
      user['employee_number'],
      user['username'],
    ];

    for (final value in possibleValues) {
      if (value == null) {
        continue;
      }

      final result = value.toString().trim();

      if (result.isNotEmpty) {
        return result;
      }
    }

    return '';
  }

  // ============================================================
  // EXTRAER NOMBRE
  // ============================================================

  String _extractUserName(
    Map<String, dynamic> user,
  ) {
    final possibleValues = [
      user['name'],
      user['username'],
      user['nombre'],
    ];

    for (final value in possibleValues) {
      if (value == null) {
        continue;
      }

      final result = value.toString().trim();

      if (result.isNotEmpty) {
        return result;
      }
    }

    return 'Usuario';
  }

  // ============================================================
  // CONVERTIR ID
  // ============================================================

  int _parsePositiveInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.toInt();
    }

    return int.tryParse(
          value.toString().trim(),
        ) ??
        0;
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    await AppStorage().logOut();
  }

  // ============================================================
  // COMPROBAR SESIÓN
  // ============================================================

  Future<bool> hasSession() async {
    final token = await AppStorage().getToken();
    final loggedIn = await AppStorage().isLoggedIn();

    return loggedIn &&
        (token ?? '').trim().isNotEmpty;
  }
}
