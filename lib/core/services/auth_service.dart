import '../demo/offline_demo_data.dart';
import '../network/api_client.dart';
import '../storage/app_storage.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    if (OfflineDemoData.isOfflineDemoUser(identifier, password)) {
      final user = OfflineDemoData.userForIdentifier(identifier)!;
      final payload = OfflineDemoData.loginPayloadFor(identifier);

      await AppStorage().saveSession(
        token: payload['token'] as String,
        userId: user.userId,
        empresaId: user.companyId,
        userName: user.name,
        isLoggedIn: true,
      );

      return payload;
    }

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
