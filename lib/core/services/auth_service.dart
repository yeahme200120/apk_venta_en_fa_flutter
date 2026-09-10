import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();

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
      final payload = await _apiClient.login(
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
      final offline = await loginOffline(
        identifier: cleanIdentifier,
        password: password,
      );

      if (offline) {
        return {
          'offline': true,
          'token': null,
          'user': {
            'id': await AppStorage().getUserId(),
            'name': await AppStorage().getUserName() ?? 'Usuario',
            'numero_usuario': cleanIdentifier,
          },
          'empresa': {
            'id': await AppStorage().getEmpresaId(),
            'nombre': await AppStorage().getCompanyName() ?? '',
          },
        };
      }

      rethrow;
    }
  }

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

    final empresa = payload['empresa'] is Map
        ? Map<String, dynamic>.from(
            payload['empresa'] as Map,
          )
        : <String, dynamic>{};

    final userId = _toInt(
      user['id'] ??
          user['user_id'],
    );

    final companyId = _toInt(
      empresa['id'] ??
          empresa['empresa_id'],
    );

    if (userId <= 0 || companyId <= 0) {
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

    String? serverBusinessDate;

    final rawDate =
        payload['business_date'] ??
        payload['fecha_negocio'] ??
        payload['fecha_operacion'] ??
        empresa['business_date'];

    if (rawDate != null) {
      if (rawDate is DateTime) {
        serverBusinessDate = rawDate.toIso8601String();
      } else {
        final parsedDate = DateTime.tryParse(
          rawDate.toString(),
        );

        serverBusinessDate =
            parsedDate?.toIso8601String() ??
            rawDate.toString();
      }
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
      offlineIdentifier: serverIdentifier,
      offlinePassword: password,
      serverBusinessDate: serverBusinessDate,
    );

    if (companyName.isNotEmpty) {
      await AppStorage().saveCompanyName(
        companyName,
      );
    }

    if (role.isNotEmpty) {
      await AppStorage().saveRol(role);
    }

    final configuration =
        empresa['configuracion'];

    if (configuration is Map) {
      final settings =
          Map<String, dynamic>.from(
        configuration,
      );

      await AppStorage().saveOperationState({
        'cajas_activas':
            settings['cajas_activas'] == true,
        'mesas_activas':
            settings['mesas_activas'] == true,
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
  }

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

    final available =
        await AppStorage()
            .isOfflineLoginAvailable();

    if (!available) {
      return false;
    }

    final savedIdentifier =
        await AppStorage()
            .getOfflineIdentifier();

    final savedPassword =
        await AppStorage()
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
        await AppStorage()
            .getLastOnlineUserId();

    final companyId =
        await AppStorage()
            .getLastOnlineEmpresaId();

    if (userId == null ||
        companyId == null ||
        userId <= 0 ||
        companyId <= 0) {
      return false;
    }

    await AppStorage().saveOfflineSession(
      userId: userId,
      empresaId: companyId,
      userName:
          await AppStorage().getUserName() ??
          'Usuario',
      companyName:
          await AppStorage().getCompanyName(),
      role:
          await AppStorage().getRole(),
    );

    final token =
        await AppStorage().getToken();

    return token == null ||
        token.trim().isEmpty;
  }

  Future<void> logout() async {
    await AppStorage().logOut();
  }

  Future<bool> hasSession() async {
    final storage = AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final token =
        await storage.getToken();

    if (token != null &&
        token.trim().isNotEmpty) {
      return true;
    }

    return storage.isOfflineSession();
  }

  Future<bool> hasOnlineSession() async {
    final storage = AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final token =
        await storage.getToken();

    return token != null &&
        token.trim().isNotEmpty;
  }

  Future<String?> getToken() async {
    final token =
        await AppStorage().getToken();

    if (token == null ||
        token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          '${value ?? ''}',
        ) ??
        0;
  }
}
