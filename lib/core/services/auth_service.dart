import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty) {
      throw Exception('Ingresa tu usuario o número de usuario.');
    }
    if (password.isEmpty) {
      throw Exception('Ingresa tu contraseña.');
    }

    try {
      final payload = await _apiClient.login(
        identifier: cleanIdentifier,
        password: password,
      );
      await _saveOnlineSession(payload, cleanIdentifier, password);
      return payload;
    } catch (error) {
      // Si no hay conectividad o el servidor no está disponible, intentamos
      // únicamente con las credenciales previamente validadas y almacenadas.
      // No se usa una cuenta demo ni se inventa una identidad local.
      final offline = await loginOffline(
        identifier: cleanIdentifier,
        password: password,
      );
      if (offline) {
        return {
          'offline': true,
          'token': 'offline-session',
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
    final token = (payload['token'] ?? payload['access_token'] ?? '').toString();
    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : <String, dynamic>{};
    final empresa = payload['empresa'] is Map
        ? Map<String, dynamic>.from(payload['empresa'] as Map)
        : <String, dynamic>{};

    final userId = _toInt(user['id'] ?? user['user_id']);
    final companyId = _toInt(empresa['id'] ?? empresa['empresa_id']);

    if (token.isEmpty || userId <= 0 || companyId <= 0) {
      throw Exception('El servidor devolvió una sesión incompleta.');
    }

    final serverIdentifier = (user['numero_usuario'] ??
            user['numero_empleado'] ??
            user['numero_socio'] ??
            user['employee_number'] ??
            user['username'] ??
            identifier)
        .toString()
        .trim();

    if (serverIdentifier.isEmpty) {
      throw Exception('El usuario recibido por el servidor no es válido.');
    }

    DateTime? serverDate;
    final rawDate = payload['business_date'] ??
        payload['fecha_negocio'] ??
        payload['fecha_operacion'] ??
        empresa['business_date'];
    if (rawDate != null) {
      serverDate = DateTime.tryParse(rawDate.toString());
    }

    final userName =
        (user['name'] ?? user['username'] ?? 'Usuario').toString();

    await AppStorage().saveSession(
      token: token,
      userId: userId,
      empresaId: companyId,
      userName: userName,
      isLoggedIn: true,
      offlineIdentifier: identifier,
      offlinePassword: password,
      serverBusinessDate: serverDate,
    );

    final companyName = empresa['nombre'] ?? empresa['name'];
    if (companyName != null) {
      await AppStorage().saveCompanyName(companyName.toString());
    }

    // Persistir el rol del usuario para uso offline (tab Caja, permisos).
    final rolRaw = user['rol'] ?? user['role'] ?? user['tipo_usuario'] ?? '';
    if (rolRaw.toString().trim().isNotEmpty) {
      await AppStorage().saveRol(rolRaw.toString().trim().toLowerCase());
    }

    final configuration = empresa['configuracion'];
    if (configuration is Map) {
      await AppStorage().saveOperationState({
        'cajas_activas': configuration['cajas_activas'] == true,
        'mesas_activas': configuration['mesas_activas'] == true,
        'caja_abierta': null,
      });
    }
  }

  Future<bool> loginOffline({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();
    if (cleanIdentifier.isEmpty || password.isEmpty) return false;

    final available = await AppStorage().isOfflineLoginAvailable();
    if (!available) return false;

    final savedIdentifier = await AppStorage().getOfflineIdentifier();
    final savedPassword = await AppStorage().getOfflinePassword();

    if (savedIdentifier == null || savedPassword == null) return false;
    if (savedIdentifier.trim() != cleanIdentifier || savedPassword != password) {
      return false;
    }

    final userId = await AppStorage().getLastOnlineUserId();
    final companyId = await AppStorage().getLastOnlineEmpresaId();
    if (userId == null || companyId == null || userId <= 0 || companyId <= 0) {
      return false;
    }

    await AppStorage().saveSession(
      token: 'offline-session',
      userId: userId,
      empresaId: companyId,
      userName: await AppStorage().getUserName() ?? 'Usuario',
      isLoggedIn: true,
    );

    return true;
  }

  Future<void> logout() => AppStorage().logOut();

  Future<bool> hasSession() async {
    final token = await AppStorage().getToken();
    return (await AppStorage().isLoggedIn()) &&
        token != null &&
        token.isNotEmpty;
  }

  int _toInt(dynamic value) {
    return value is num
        ? value.toInt()
        : int.tryParse('${value ?? ''}') ?? 0;
  }
}
