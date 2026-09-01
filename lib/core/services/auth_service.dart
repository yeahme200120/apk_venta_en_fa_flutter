import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    // 🔥 Ya no hay usuarios demo: todos los logins van al backend.
    final payload = await _apiClient.login(
      identifier: identifier,
      password: password,
    );

    final token = (payload['token'] ?? payload['access_token'] ?? '').toString();
    final user = payload['user'] is Map ? payload['user'] as Map<String, dynamic> : <String, dynamic>{};
    final empresa = payload['empresa'] is Map ? payload['empresa'] as Map<String, dynamic> : <String, dynamic>{};

    await AppStorage().saveSession(
      token: token,
      userId: int.tryParse('${user['id'] ?? user['user_id'] ?? 0}') ?? 0,
      empresaId: int.tryParse('${empresa['id'] ?? empresa['empresa_id'] ?? 0}') ?? 0,
      userName: (user['name'] ?? user['username'] ?? 'Usuario').toString(),
      isLoggedIn: true,
    );

    final companyName = empresa['nombre'] ?? empresa['name'];
    if (companyName != null) {
      await AppStorage().saveCompanyName(companyName.toString());
    }

    final configuration = empresa['configuracion'];
    if (configuration is Map) {
      final settings = Map<String, dynamic>.from(configuration);
      await AppStorage().saveOperationState({
        'cajas_activas': settings['cajas_activas'] == true,
        'mesas_activas': settings['mesas_activas'] == true,
        'caja_abierta': null,
      });
    }

    return payload;
  }

  Future<void> logout() async {
    await AppStorage().logOut();
  }

  Future<bool> hasSession() async {
    final token = await AppStorage().getToken();
    final loggedIn = await AppStorage().isLoggedIn();
    return loggedIn && (token ?? '').isNotEmpty;
  }
}