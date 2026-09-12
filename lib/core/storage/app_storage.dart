import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static final AppStorage _instance =
      AppStorage._internal();

  factory AppStorage() => _instance;

  AppStorage._internal();

  // ============================================================
  // CLAVES
  // ============================================================

  static const String _tokenKey = 'token';
  static const String _userIdKey = 'user_id';
  static const String _empresaIdKey = 'empresa_id';
  static const String _userNameKey = 'user_name';
  static const String _companyNameKey = 'company_name';
  static const String _loggedKey = 'is_logged_in';
  static const String _roleKey = 'role';

  static const String _offlineIdentifierKey =
      'offline_identifier';

  static const String _offlinePasswordKey =
      'offline_password';

  static const String _lastOnlineUserIdKey =
      'last_online_user_id';

  static const String _lastOnlineEmpresaIdKey =
      'last_online_empresa_id';

  static const String _lastOnlineAtKey =
      'last_online_at';

  static const String _businessDateKey =
      'server_business_date';

  static const String _ticketConfigKey =
      'ticket_config';

  static const String _operationStateKey =
      'operation_state';

  // Indica si las credenciales offline pertenecen
  // al día comercial actualmente autorizado.
  static const String _offlineDayValidKey =
      'offline_day_valid';

  // ============================================================
  // LIMPIAR STORAGE
  // ============================================================

  Future<void> clear() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.clear();
  }

  // ============================================================
  // SESIÓN ONLINE
  // ============================================================

  Future<void> saveSession({
    required String token,
    required int userId,
    required int empresaId,
    required String userName,
    required bool isLoggedIn,
    String? offlineIdentifier,
    String? offlinePassword,
    String? serverBusinessDate,
  }) async {
    final prefs =
        await SharedPreferences.getInstance();

    final cleanToken = token.trim();

    if (cleanToken.isEmpty) {
      throw ArgumentError(
        'El token de sesión no puede estar vacío.',
      );
    }

    if (userId <= 0) {
      throw ArgumentError(
        'El ID del usuario no es válido.',
      );
    }

    if (empresaId <= 0) {
      throw ArgumentError(
        'El ID de la empresa no es válido.',
      );
    }

    await prefs.setString(
      _tokenKey,
      cleanToken,
    );

    await prefs.setInt(
      _userIdKey,
      userId,
    );

    await prefs.setInt(
      _empresaIdKey,
      empresaId,
    );

    await prefs.setString(
      _userNameKey,
      userName.trim(),
    );

    await prefs.setBool(
      _loggedKey,
      isLoggedIn,
    );

    // Última sesión ONLINE válida.
    await prefs.setInt(
      _lastOnlineUserIdKey,
      userId,
    );

    await prefs.setInt(
      _lastOnlineEmpresaIdKey,
      empresaId,
    );

    await prefs.setString(
      _lastOnlineAtKey,
      DateTime.now().toIso8601String(),
    );

    if (offlineIdentifier != null &&
        offlineIdentifier.trim().isNotEmpty) {
      await prefs.setString(
        _offlineIdentifierKey,
        offlineIdentifier.trim(),
      );
    }

    if (offlinePassword != null) {
      await prefs.setString(
        _offlinePasswordKey,
        offlinePassword,
      );
    }

    if (serverBusinessDate != null &&
        serverBusinessDate.trim().isNotEmpty) {
      await prefs.setString(
        _businessDateKey,
        serverBusinessDate.trim(),
      );

      // Las credenciales offline quedan asociadas
      // al día comercial que acaba de validar el servidor.
      await prefs.setBool(
        _offlineDayValidKey,
        true,
      );
    }
  }

  // ============================================================
  // SESIÓN OFFLINE
  // ============================================================

  Future<void> saveOfflineSession({
    required int userId,
    required int empresaId,
    required String userName,
    String? companyName,
    String? role,
  }) async {
    final prefs =
        await SharedPreferences.getInstance();

    // Una sesión offline no debe conservar un Bearer token.
    await prefs.remove(
      _tokenKey,
    );

    await prefs.setInt(
      _userIdKey,
      userId,
    );

    await prefs.setInt(
      _empresaIdKey,
      empresaId,
    );

    await prefs.setString(
      _userNameKey,
      userName.trim(),
    );

    await prefs.setBool(
      _loggedKey,
      true,
    );

    // Conservamos la identidad de la última sesión online.
    await prefs.setInt(
      _lastOnlineUserIdKey,
      userId,
    );

    await prefs.setInt(
      _lastOnlineEmpresaIdKey,
      empresaId,
    );

    if (companyName != null &&
        companyName.trim().isNotEmpty) {
      await prefs.setString(
        _companyNameKey,
        companyName.trim(),
      );
    }

    if (role != null &&
        role.trim().isNotEmpty) {
      await saveRol(role);
    }
  }

  // ============================================================
  // TOKEN
  // ============================================================

  Future<String?> getToken() async {
    final prefs =
        await SharedPreferences.getInstance();

    final token =
        prefs.getString(_tokenKey);

    if (token == null ||
        token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  // ============================================================
  // USUARIO
  // ============================================================

  Future<int?> getUserId() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getInt(
      _userIdKey,
    );
  }

  Future<int?> getEmpresaId() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getInt(
      _empresaIdKey,
    );
  }

  Future<String?> getUserName() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _userNameKey,
    );
  }

  // ============================================================
  // EMPRESA
  // ============================================================

  Future<void> saveCompanyName(
    String name,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _companyNameKey,
      name.trim(),
    );
  }

  Future<String?> getCompanyName() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _companyNameKey,
    );
  }

  // ============================================================
  // ROL
  // ============================================================

  Future<void> saveRol(
    String role,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    final normalized =
        role.trim().toLowerCase();

    if (normalized.isEmpty) {
      await prefs.remove(
        _roleKey,
      );
      return;
    }

    await prefs.setString(
      _roleKey,
      normalized,
    );
  }

  Future<String?> getRole() async {
    final prefs =
        await SharedPreferences.getInstance();

    final role =
        prefs.getString(
      _roleKey,
    );

    if (role == null ||
        role.trim().isEmpty) {
      return null;
    }

    return role.trim().toLowerCase();
  }

  // Compatibilidad con código existente.
  Future<String?> getRol() async {
    return getRole();
  }

  // Roles autorizados para Caja.
  Future<bool> isCajero() async {
    final role =
        (await getRole())
                ?.trim()
                .toLowerCase() ??
            '';

    return role == 'cajero' ||
        role == 'admin' ||
        role == 'superadmin';
  }

  // ============================================================
  // CONFIGURACIÓN DEL TICKET
  // ============================================================

  Future<void> saveTicketConfig(
    Map<String, dynamic> config,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _ticketConfigKey,
      jsonEncode(config),
    );
  }

  Future<Map<String, dynamic>>
      getTicketConfig() async {
    final prefs =
        await SharedPreferences.getInstance();

    final value =
        prefs.getString(
      _ticketConfigKey,
    );

    if (value == null ||
        value.trim().isEmpty) {
      return {};
    }

    try {
      final decoded =
          jsonDecode(value);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {}

    return {};
  }

  // ============================================================
  // ESTADO OPERATIVO
  // ============================================================

  Future<void> saveOperationState(
    Map<String, dynamic> state,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _operationStateKey,
      jsonEncode(state),
    );
  }

  Future<Map<String, dynamic>>
      getOperationState() async {
    final prefs =
        await SharedPreferences.getInstance();

    final value =
        prefs.getString(
      _operationStateKey,
    );

    if (value == null ||
        value.trim().isEmpty) {
      return {};
    }

    try {
      final decoded =
          jsonDecode(value);

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (_) {}

    return {};
  }

  // ============================================================
  // ESTADO DE LOGIN
  // ============================================================

  Future<bool> isLoggedIn() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(
          _loggedKey,
        ) ??
        false;
  }

  // ============================================================
  // FECHA COMERCIAL DEL SERVIDOR
  // ============================================================

  Future<void> saveServerBusinessDate(
    String? value,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    if (value == null ||
        value.trim().isEmpty) {
      await prefs.remove(
        _businessDateKey,
      );
      return;
    }

    await prefs.setString(
      _businessDateKey,
      value.trim(),
    );
  }

  Future<String?> getServerBusinessDate() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _businessDateKey,
    );
  }

  // Compatibilidad con SettingsScreen.
  Future<String?> getBusinessDate() async {
    return getServerBusinessDate();
  }

  // Compatibilidad con SettingsScreen.
  Future<void> saveBusinessDate(
    String? value,
  ) async {
    await saveServerBusinessDate(
      value,
    );
  }

  // ============================================================
  // ÚLTIMA CONEXIÓN ONLINE
  // ============================================================

  Future<String?> getLastOnlineAt() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _lastOnlineAtKey,
    );
  }

  // ============================================================
  // CREDENCIALES OFFLINE
  // ============================================================

  Future<void> saveOfflineCredentials({
    required String identifier,
    required String password,
  }) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      _offlineIdentifierKey,
      identifier.trim(),
    );

    await prefs.setString(
      _offlinePasswordKey,
      password,
    );

    await prefs.setBool(
      _offlineDayValidKey,
      true,
    );
  }

  Future<String?> getOfflineIdentifier() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _offlineIdentifierKey,
    );
  }

  Future<String?> getOfflinePassword() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _offlinePasswordKey,
    );
  }

  Future<bool> isOfflineLoginAvailable() async {
    final identifier =
        await getOfflineIdentifier();

    final password =
        await getOfflinePassword();

    final userId =
        await getLastOnlineUserId();

    final empresaId =
        await getLastOnlineEmpresaId();

    final dayValid =
        await isOfflineDayValid();

    return identifier != null &&
        identifier.trim().isNotEmpty &&
        password != null &&
        password.isNotEmpty &&
        userId != null &&
        userId > 0 &&
        empresaId != null &&
        empresaId > 0 &&
        dayValid;
  }

  Future<int?> getLastOnlineUserId() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getInt(
      _lastOnlineUserIdKey,
    );
  }

  Future<int?> getLastOnlineEmpresaId() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getInt(
      _lastOnlineEmpresaIdKey,
    );
  }

  // ============================================================
  // VALIDACIÓN DEL DÍA OFFLINE
  // ============================================================

  Future<void> saveOfflineDayValid(
    bool value,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      _offlineDayValidKey,
      value,
    );
  }

  Future<bool> isOfflineDayValid() async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getBool(
          _offlineDayValidKey,
        ) ??
        false;
  }

  // ============================================================
  // INVALIDAR SESIÓN POR CAMBIO DE DÍA COMERCIAL
  // ============================================================

  Future<void>
      invalidateSessionForBusinessDateChange() async {
    final prefs =
        await SharedPreferences.getInstance();

    // Sesión activa.
    await prefs.remove(
      _tokenKey,
    );

    await prefs.remove(
      _userIdKey,
    );

    await prefs.remove(
      _empresaIdKey,
    );

    await prefs.remove(
      _userNameKey,
    );

    await prefs.remove(
      _companyNameKey,
    );

    await prefs.remove(
      _roleKey,
    );

    await prefs.remove(
      _loggedKey,
    );

    // Las credenciales anteriores ya no pueden
    // utilizarse para entrar offline al nuevo día.
    await prefs.remove(
      _offlineIdentifierKey,
    );

    await prefs.remove(
      _offlinePasswordKey,
    );

    await prefs.remove(
      _lastOnlineUserIdKey,
    );

    await prefs.remove(
      _lastOnlineEmpresaIdKey,
    );

    await prefs.remove(
      _lastOnlineAtKey,
    );

    await prefs.setBool(
      _offlineDayValidKey,
      false,
    );

    // La fecha comercial se elimina para que
    // el siguiente login online establezca
    // explícitamente la nueva fecha autorizada.
    await prefs.remove(
      _businessDateKey,
    );

    // No eliminamos:
    // - ticket_config
    // - operation_state
    //
    // La configuración persistente no pertenece
    // exclusivamente al día operativo.
  }

  // ============================================================
  // SESIÓN OFFLINE ACTIVA
  // ============================================================

  Future<bool> isOfflineSession() async {
    if (!await isLoggedIn()) {
      return false;
    }

    final token =
        await getToken();

    if (token != null &&
        token.trim().isNotEmpty) {
      return false;
    }

    return isOfflineLoginAvailable();
  }

  // ============================================================
  // CERRAR SESIÓN
  // ============================================================

  Future<void> logOut() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.remove(
      _tokenKey,
    );

    await prefs.remove(
      _userIdKey,
    );

    await prefs.remove(
      _empresaIdKey,
    );

    await prefs.remove(
      _userNameKey,
    );

    await prefs.remove(
      _companyNameKey,
    );

    await prefs.remove(
      _roleKey,
    );

    await prefs.remove(
      _loggedKey,
    );

    // No eliminamos:
    // - credenciales offline
    // - últimos IDs online
    // - fecha comercial
    // - última conexión
    //
    // Esto permite volver a iniciar sesión sin internet.
    //
    // Tampoco invalidamos _offlineDayValidKey:
    // cerrar sesión normal no significa cambio de día.
  }
}
