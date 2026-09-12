import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient();

  // ============================================================
  // LOGIN
  // ============================================================

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier =
        identifier.trim();

    if (cleanIdentifier.isEmpty) {
      throw Exception(
        'Ingresa tu usuario o número de usuario.',
      );
    }

    if (password.isEmpty) {
      throw Exception(
        'Ingresa tu contraseña.',
      );
    }

    try {
      final payload =
          await _apiClient.login(
        identifier: cleanIdentifier,
        password: password,
      );

      await _saveOnlineSession(
        payload,
        cleanIdentifier,
        password,
      );

      return payload;
    } catch (error) {
      // IMPORTANTE:
      //
      // No se intenta login offline ante cualquier error.
      //
      // Si las credenciales fueron rechazadas por el servidor,
      // el usuario debe corregirlas.
      //
      // El fallback offline solo se permite cuando existe
      // una cuenta local previamente validada y el error
      // corresponde a falta de conectividad.
      if (!_isNetworkError(error)) {
        rethrow;
      }

      final offline =
          await loginOffline(
        identifier: cleanIdentifier,
        password: password,
      );

      if (!offline) {
        rethrow;
      }

      return {
        'offline': true,
        'token': null,
        'user': {
          'id':
              await AppStorage().getUserId(),
          'name':
              await AppStorage()
                      .getUserName() ??
                  'Usuario',
          'numero_usuario':
              cleanIdentifier,
        },
        'empresa': {
          'id':
              await AppStorage()
                  .getEmpresaId(),
          'nombre':
              await AppStorage()
                      .getCompanyName() ??
                  '',
        },
      };
    }
  }

  // ============================================================
  // GUARDAR SESIÓN ONLINE
  // ============================================================

  Future<void> _saveOnlineSession(
    Map<String, dynamic> payload,
    String identifier,
    String password,
  ) async {
    final token = (
      payload['access_token'] ??
      payload['token'] ??
      ''
    ).toString().trim();

    if (token.isEmpty) {
      throw Exception(
        'El servidor no devolvió un token de acceso.',
      );
    }

    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(
            payload['user'] as Map,
          )
        : <String, dynamic>{};

    final empresa =
        payload['empresa'] is Map
            ? Map<String, dynamic>.from(
                payload['empresa'] as Map,
              )
            : <String, dynamic>{};

    final userId =
        _toInt(
      user['id'] ??
          user['user_id'],
    );

    final companyId =
        _toInt(
      empresa['id'] ??
          empresa['empresa_id'],
    );

    if (userId <= 0 ||
        companyId <= 0) {
      throw Exception(
        'El servidor devolvió una sesión incompleta.',
      );
    }

    final serverIdentifier = (
      user['numero_usuario'] ??
      user['numero_empleado'] ??
      user['numero_socio'] ??
      user['employee_number'] ??
      user['username'] ??
      identifier
    ).toString().trim();

    if (serverIdentifier.isEmpty) {
      throw Exception(
        'El usuario recibido por el servidor no es válido.',
      );
    }

    final serverBusinessDate =
        _extractBusinessDate(
      payload,
      empresa,
    );

    if (serverBusinessDate == null ||
        serverBusinessDate.trim().isEmpty) {
      throw Exception(
        'El servidor no devolvió la fecha comercial.',
      );
    }

    final userName = (
      user['name'] ??
      user['username'] ??
      'Usuario'
    ).toString().trim();

    final companyName = (
      empresa['nombre'] ??
      empresa['name'] ??
      ''
    ).toString().trim();

    final role = (
      user['rol'] ??
      user['role'] ??
      user['tipo_usuario'] ??
      ''
    ).toString().trim().toLowerCase();

    await AppStorage().saveSession(
      token: token,
      userId: userId,
      empresaId: companyId,
      userName: userName,
      isLoggedIn: true,
      offlineIdentifier:
          serverIdentifier,
      offlinePassword: password,
      serverBusinessDate:
          serverBusinessDate,
    );

    if (companyName.isNotEmpty) {
      await AppStorage().saveCompanyName(
        companyName,
      );
    }

    if (role.isNotEmpty) {
      await AppStorage().saveRol(
        role,
      );
    }

    final configuration =
        empresa['configuracion'];

    if (configuration is Map) {
      final settings =
          Map<String, dynamic>.from(
        configuration,
      );

      await AppStorage()
          .saveOperationState({
        'cajas_activas':
            settings['cajas_activas'] ==
                true,
        'mesas_activas':
            settings['mesas_activas'] ==
                true,
        'caja_abierta': null,
      });
    }

    final savedToken =
        await AppStorage().getToken();

    if (savedToken == null ||
        savedToken.trim().isEmpty) {
      throw Exception(
        'El token no pudo guardarse correctamente.',
      );
    }

    if (savedToken.trim() != token) {
      throw Exception(
        'El token guardado no coincide con el token recibido.',
      );
    }

    final savedUserId =
        await AppStorage().getUserId();

    final savedCompanyId =
        await AppStorage().getEmpresaId();

    if (savedUserId != userId ||
        savedCompanyId != companyId) {
      throw Exception(
        'La sesión local no pudo guardarse correctamente.',
      );
    }

    if (!await AppStorage()
        .isOfflineDayValid()) {
      throw Exception(
        'La sesión offline no quedó habilitada correctamente.',
      );
    }
  }

  // ============================================================
  // LOGIN OFFLINE
  // ============================================================

  Future<bool> loginOffline({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier =
        identifier.trim();

    if (cleanIdentifier.isEmpty ||
        password.isEmpty) {
      return false;
    }

    final storage =
        AppStorage();

    final available =
        await storage
            .isOfflineLoginAvailable();

    if (!available) {
      return false;
    }

    final savedIdentifier =
        await storage
            .getOfflineIdentifier();

    final savedPassword =
        await storage
            .getOfflinePassword();

    if (savedIdentifier == null ||
        savedPassword == null) {
      return false;
    }

    if (savedIdentifier.trim() !=
            cleanIdentifier ||
        savedPassword != password) {
      return false;
    }

    final userId =
        await storage
            .getLastOnlineUserId();

    final companyId =
        await storage
            .getLastOnlineEmpresaId();

    if (userId == null ||
        companyId == null ||
        userId <= 0 ||
        companyId <= 0) {
      return false;
    }

    final businessDate =
        await storage
            .getServerBusinessDate();

    if (businessDate == null ||
        businessDate.trim().isEmpty) {
      return false;
    }

    await storage.saveOfflineSession(
      userId: userId,
      empresaId: companyId,
      userName:
          await storage.getUserName() ??
              'Usuario',
      companyName:
          await storage.getCompanyName(),
      role:
          await storage.getRole(),
    );

    final token =
        await storage.getToken();

    return token == null ||
        token.trim().isEmpty;
  }

  // ============================================================
  // SESIÓN
  // ============================================================

  Future<void> logout() async {
    await AppStorage().logOut();
  }

  Future<bool> hasSession() async {
    final storage =
        AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final userId =
        await storage.getUserId();

    final companyId =
        await storage.getEmpresaId();

    if (userId == null ||
        companyId == null ||
        userId <= 0 ||
        companyId <= 0) {
      await storage.logOut();
      return false;
    }

    final token =
        await storage.getToken();

    // ----------------------------------------------------------
    // SESIÓN ONLINE
    // ----------------------------------------------------------

    if (token != null &&
        token.trim().isNotEmpty) {
      try {
        final currentUser =
            await _apiClient
                .getCurrentUser();

        final serverDate =
            _extractBusinessDateFromUser(
          currentUser,
        );

        if (serverDate != null &&
            serverDate.trim().isNotEmpty) {
          final localDate =
              await storage
                  .getServerBusinessDate();

          if (localDate != null &&
              _normalizeBusinessDate(
                    localDate,
                  ) !=
                  _normalizeBusinessDate(
                    serverDate,
                  )) {
            // La sesión existe, pero pertenece
            // a un día comercial anterior.
            //
            // SplashScreen puede consultar este estado
            // mediante checkBusinessDate().
            return false;
          }
        }

        return true;
      } catch (error) {
        // Si el servidor no está disponible,
        // NO destruimos una sesión local válida.
        //
        // Esto permite continuar trabajando offline.
        if (_isNetworkError(error)) {
          return storage.isOfflineDayValid();
        }

        // Cualquier error de autenticación/servidor
        // que no sea conectividad invalida la sesión.
        await storage.logOut();

        return false;
      }
    }

    // ----------------------------------------------------------
    // SESIÓN OFFLINE
    // ----------------------------------------------------------

    return storage.isOfflineSession();
  }

  // ============================================================
  // SESIÓN ONLINE
  // ============================================================

  Future<bool> hasOnlineSession() async {
    final storage =
        AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final token =
        await storage.getToken();

    if (token == null ||
        token.trim().isEmpty) {
      return false;
    }

    try {
      final currentUser =
          await _apiClient
              .getCurrentUser();

      final serverDate =
          _extractBusinessDateFromUser(
        currentUser,
      );

      if (serverDate != null &&
          serverDate.trim().isNotEmpty) {
        final localDate =
            await storage
                .getServerBusinessDate();

        if (localDate != null &&
            _normalizeBusinessDate(
                  localDate,
                ) !=
                _normalizeBusinessDate(
                  serverDate,
                )) {
          return false;
        }
      }

      return true;
    } catch (error) {
      if (_isNetworkError(error)) {
        return true;
      }

      await storage.logOut();

      return false;
    }
  }

  // ============================================================
  // VALIDAR FECHA COMERCIAL
  // ============================================================

  Future<bool> hasBusinessDateChanged() async {
    final storage =
        AppStorage();

    final token =
        await storage.getToken();

    if (token == null ||
        token.trim().isEmpty) {
      return false;
    }

    try {
      final currentUser =
          await _apiClient
              .getCurrentUser();

      final serverDate =
          _extractBusinessDateFromUser(
        currentUser,
      );

      if (serverDate == null ||
          serverDate.trim().isEmpty) {
        return false;
      }

      final localDate =
          await storage
              .getServerBusinessDate();

      if (localDate == null ||
          localDate.trim().isEmpty) {
        return false;
      }

      return _normalizeBusinessDate(
            localDate,
          ) !=
          _normalizeBusinessDate(
            serverDate,
          );
    } catch (error) {
      // Sin conexión no se debe asumir cambio de día.
      if (_isNetworkError(error)) {
        return false;
      }

      rethrow;
    }
  }

  // ============================================================
  // INFORMACIÓN DE FECHA COMERCIAL
  // ============================================================

  Future<String?> getCurrentServerBusinessDate()
      async {
    try {
      final currentUser =
          await _apiClient
              .getCurrentUser();

      return _extractBusinessDateFromUser(
        currentUser,
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // TOKEN
  // ============================================================

  Future<String?> getToken() async {
    final token =
        await AppStorage().getToken();

    if (token == null ||
        token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String? _extractBusinessDate(
    Map<String, dynamic> payload,
    Map<String, dynamic> empresa,
  ) {
    final rawDate =
        payload['business_date'] ??
        payload['fecha_negocio'] ??
        payload['fecha_operacion'] ??
        payload['fecha_comercial'] ??
        empresa['business_date'] ??
        empresa['fecha_negocio'] ??
        empresa['fecha_operacion'] ??
        empresa['fecha_comercial'];

    return _normalizeBusinessDateValue(
      rawDate,
    );
  }

  String? _extractBusinessDateFromUser(
    Map<String, dynamic> payload,
  ) {
    final empresa =
        payload['empresa'] is Map
            ? Map<String, dynamic>.from(
                payload['empresa'] as Map,
              )
            : <String, dynamic>{};

    final rawDate =
        payload['business_date'] ??
        payload['fecha_negocio'] ??
        payload['fecha_operacion'] ??
        payload['fecha_comercial'] ??
        empresa['business_date'] ??
        empresa['fecha_negocio'] ??
        empresa['fecha_operacion'] ??
        empresa['fecha_comercial'];

    return _normalizeBusinessDateValue(
      rawDate,
    );
  }

  String? _normalizeBusinessDateValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    final text =
        value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    final parsed =
        DateTime.tryParse(text);

    return parsed?.toIso8601String() ??
        text;
  }

  String _normalizeBusinessDate(
    String value,
  ) {
    final clean =
        value.trim();

    final parsed =
        DateTime.tryParse(clean);

    if (parsed != null) {
      return parsed
          .toIso8601String()
          .substring(0, 10);
    }

    // Si el backend ya entrega YYYY-MM-DD.
    if (clean.length >= 10) {
      return clean.substring(0, 10);
    }

    return clean;
  }

  bool _isNetworkError(
    Object error,
  ) {
    final message =
        error.toString().toLowerCase();

    const networkTerms = [
      'connection',
      'network',
      'socket',
      'timeout',
      'timed out',
      'connection refused',
      'connection reset',
      'connection aborted',
      'host lookup',
      'failed host lookup',
      'internet',
      'dns',
      'unreachable',
      'receive timeout',
      'connect timeout',
    ];

    for (final term in networkTerms) {
      if (message.contains(term)) {
        return true;
      }
    }

    return false;
  }

  int _toInt(
    dynamic value,
  ) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          '${value ?? ''}',
        ) ??
        0;
  }
}
