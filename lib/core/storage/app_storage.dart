import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AppStorage {
  static final AppStorage _instance = AppStorage._internal();

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
  static const String _licenseSnapshotKey = 'license_snapshot';

  static const String _offlineIdentifierKey = 'offline_identifier';

  static const String _offlinePasswordKey = 'offline_password';

  static const String _lastOnlineUserIdKey = 'last_online_user_id';

  static const String _lastOnlineEmpresaIdKey = 'last_online_empresa_id';

  static const String _lastOnlineAtKey = 'last_online_at';

  static const String _businessDateKey = 'server_business_date';

  static const String _ticketConfigKey = 'ticket_config';

  static const String _operationStateKey = 'operation_state';

  // Indica si las credenciales offline pertenecen
  // al día comercial actualmente autorizado.
  static const String _offlineDayValidKey = 'offline_day_valid';

  // Marca que el catálogo local debe purgarse antes
  // de aplicar el próximo sync de catálogos.
  //
  // Se activa en cada login online para garantizar que un
  // dispositivo que antes estaba vinculado a otra empresa
  // no conserve productos/categorías ajenos.
  static const String _catalogPurgePendingKey = 'catalog_purge_pending';

  // ============================================================
  // LIMPIAR STORAGE
  // ============================================================

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

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
    final prefs = await SharedPreferences.getInstance();

    final cleanToken = token.trim();

    if (cleanToken.isEmpty) {
      throw ArgumentError('El token de sesión no puede estar vacío.');
    }

    if (userId <= 0) {
      throw ArgumentError('El ID del usuario no es válido.');
    }

    if (empresaId <= 0) {
      throw ArgumentError('El ID de la empresa no es válido.');
    }

    await prefs.setString(_tokenKey, cleanToken);

    await prefs.setInt(_userIdKey, userId);

    await prefs.setInt(_empresaIdKey, empresaId);

    await prefs.setString(_userNameKey, userName.trim());

    await prefs.setBool(_loggedKey, isLoggedIn);

    // Última sesión ONLINE válida.
    await prefs.setInt(_lastOnlineUserIdKey, userId);

    await prefs.setInt(_lastOnlineEmpresaIdKey, empresaId);

    await prefs.setString(_lastOnlineAtKey, DateTime.now().toIso8601String());

    if (offlineIdentifier != null && offlineIdentifier.trim().isNotEmpty) {
      await prefs.setString(_offlineIdentifierKey, offlineIdentifier.trim());
    }

    if (offlinePassword != null) {
      await prefs.setString(_offlinePasswordKey, offlinePassword);
    }

    if (serverBusinessDate != null && serverBusinessDate.trim().isNotEmpty) {
      await prefs.setString(_businessDateKey, serverBusinessDate.trim());

      // Las credenciales offline quedan asociadas
      // al día comercial que acaba de validar el servidor.
      await prefs.setBool(_offlineDayValidKey, true);
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
    final prefs = await SharedPreferences.getInstance();

    // Una sesión offline no debe conservar un Bearer token.
    await prefs.remove(_tokenKey);

    await prefs.setInt(_userIdKey, userId);

    await prefs.setInt(_empresaIdKey, empresaId);

    await prefs.setString(_userNameKey, userName.trim());

    await prefs.setBool(_loggedKey, true);

    // Conservamos la identidad de la última sesión online.
    await prefs.setInt(_lastOnlineUserIdKey, userId);

    await prefs.setInt(_lastOnlineEmpresaIdKey, empresaId);

    if (companyName != null && companyName.trim().isNotEmpty) {
      await prefs.setString(_companyNameKey, companyName.trim());
    }

    if (role != null && role.trim().isNotEmpty) {
      await saveRol(role);
    }
  }

  // ============================================================
  // TOKEN
  // ============================================================

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();

    final token = prefs.getString(_tokenKey);

    if (token == null || token.trim().isEmpty) {
      return null;
    }

    return token.trim();
  }

  // ============================================================
  // USUARIO
  // ============================================================

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(_userIdKey);
  }

  Future<int?> getEmpresaId() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(_empresaIdKey);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_userNameKey);
  }

  // ============================================================
  // EMPRESA
  // ============================================================

  Future<void> saveCompanyName(String name) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_companyNameKey, name.trim());
  }

  Future<String?> getCompanyName() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_companyNameKey);
  }

  // ============================================================
  // ROL
  // ============================================================

  Future<void> saveRol(String role) async {
    final prefs = await SharedPreferences.getInstance();

    final normalized = role.trim().toLowerCase();

    if (normalized.isEmpty) {
      await prefs.remove(_roleKey);
      return;
    }

    await prefs.setString(_roleKey, normalized);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();

    final role = prefs.getString(_roleKey);

    if (role == null || role.trim().isEmpty) {
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
    final role = (await getRole())?.trim().toLowerCase() ?? '';

    return role == 'cajero' || role == 'admin' || role == 'superadmin';
  }

  // ============================================================
  // CONFIGURACIÓN DEL TICKET
  // ============================================================

  Future<void> saveTicketConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_ticketConfigKey, jsonEncode(config));
  }

  Future<Map<String, dynamic>> getTicketConfig() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_ticketConfigKey);

    if (value == null || value.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return {};
  }

  // ============================================================
  // ESTADO OPERATIVO
  // ============================================================

  Future<void> saveOperationState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_operationStateKey, jsonEncode(state));
  }

  Future<Map<String, dynamic>> getOperationState() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_operationStateKey);

    if (value == null || value.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return {};
  }

  // ============================================================
  // ESTADO DE LOGIN
  // ============================================================

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_loggedKey) ?? false;
  }

  // ============================================================
  // FECHA COMERCIAL DEL SERVIDOR
  // ============================================================

  Future<void> saveServerBusinessDate(String? value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value == null || value.trim().isEmpty) {
      await prefs.remove(_businessDateKey);
      return;
    }

    await prefs.setString(_businessDateKey, value.trim());
  }

  Future<String?> getServerBusinessDate() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_businessDateKey);
  }

  // Compatibilidad con SettingsScreen.
  Future<String?> getBusinessDate() async {
    return getServerBusinessDate();
  }

  // Compatibilidad con SettingsScreen.
  Future<void> saveBusinessDate(String? value) async {
    await saveServerBusinessDate(value);
  }

  // ============================================================
  // FECHA COMERCIAL NORMALIZADA
  // ============================================================

  Future<String?> getServerBusinessDateKey() async {
    final raw = await getServerBusinessDate();

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(raw.trim());

    if (parsed != null) {
      return parsed.toIso8601String().substring(0, 10);
    }

    if (raw.trim().length >= 10) {
      return raw.trim().substring(0, 10);
    }

    return raw.trim();
  }

  /// Compara la fecha comercial guardada contra la que acaba
  /// de enviar el servidor.
  ///
  /// Devuelve true SOLO si ambas existen y son distintas.
  Future<bool> businessDateChanged(String newServerDate) async {
    final localKey = await getServerBusinessDateKey();

    if (localKey == null || localKey.isEmpty) {
      return false;
    }

    final newParsed = DateTime.tryParse(newServerDate.trim());

    final newKey = newParsed != null
        ? newParsed.toIso8601String().substring(0, 10)
        : newServerDate.trim().substring(0, 10);

    return localKey != newKey;
  }

  // ============================================================
  // PURGA DE CATÁLOGO
  // ============================================================
  //
  // Un dispositivo POS se usa con UNA SOLA empresa.
  //
  // Al iniciar sesión online, marcamos "purga pendiente" para que
  // el próximo sync de catálogos elimine los productos/categorías/
  // clientes/etc. que pudieran pertenecer a una empresa anterior.
  //
  // El flag se consume (se pone en false) en la primera
  // sincronización de catálogos, para que solo purgue una vez
  // por login.

  Future<void> markCatalogPurgePending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_catalogPurgePendingKey, true);
  }

  Future<bool> isCatalogPurgePending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_catalogPurgePendingKey) ?? false;
  }

  /// Devuelve true si la purga estaba pendiente y la consume.
  Future<bool> consumeCatalogPurgePending() async {
    final prefs = await SharedPreferences.getInstance();

    final wasPending = prefs.getBool(_catalogPurgePendingKey) ?? false;

    if (wasPending) {
      await prefs.setBool(_catalogPurgePendingKey, false);
    }

    return wasPending;
  }

  // ============================================================
  // ÚLTIMA CONEXIÓN ONLINE
  // ============================================================

  Future<String?> getLastOnlineAt() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_lastOnlineAtKey);
  }

  // ============================================================
  // CREDENCIALES OFFLINE
  // ============================================================

  Future<void> saveOfflineCredentials({
    required String identifier,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_offlineIdentifierKey, identifier.trim());

    await prefs.setString(_offlinePasswordKey, password);

    await prefs.setBool(_offlineDayValidKey, true);
  }

  Future<String?> getOfflineIdentifier() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_offlineIdentifierKey);
  }

  Future<String?> getOfflinePassword() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_offlinePasswordKey);
  }

  Future<bool> isOfflineLoginAvailable() async {
    final identifier = await getOfflineIdentifier();

    final password = await getOfflinePassword();

    final userId = await getLastOnlineUserId();

    final empresaId = await getLastOnlineEmpresaId();

    final dayValid = await isOfflineDayValid();

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
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(_lastOnlineUserIdKey);
  }

  Future<int?> getLastOnlineEmpresaId() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(_lastOnlineEmpresaIdKey);
  }

  // ============================================================
  // VALIDACIÓN DEL DÍA OFFLINE
  // ============================================================

  Future<void> saveOfflineDayValid(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_offlineDayValidKey, value);
  }

  Future<bool> isOfflineDayValid() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_offlineDayValidKey) ?? false;
  }

  // ============================================================
  // INVALIDAR SESIÓN POR CAMBIO DE DÍA COMERCIAL
  // ============================================================

  Future<void> invalidateSessionForBusinessDateChange() async {
    final prefs = await SharedPreferences.getInstance();

    // Sesión activa.
    await prefs.remove(_tokenKey);

    await prefs.remove(_userIdKey);

    await prefs.remove(_empresaIdKey);

    await prefs.remove(_userNameKey);

    await prefs.remove(_companyNameKey);

    await prefs.remove(_roleKey);

    await prefs.remove(_loggedKey);

    // Las credenciales anteriores ya no pueden
    // utilizarse para entrar offline al nuevo día.
    await prefs.remove(_offlineIdentifierKey);

    await prefs.remove(_offlinePasswordKey);

    await prefs.remove(_lastOnlineUserIdKey);

    await prefs.remove(_lastOnlineEmpresaIdKey);

    await prefs.remove(_lastOnlineAtKey);

    await prefs.setBool(_offlineDayValidKey, false);

    // La fecha comercial se elimina para que
    // el siguiente login online establezca
    // explícitamente la nueva fecha autorizada.
    await prefs.remove(_businessDateKey);

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

    final token = await getToken();

    if (token != null && token.trim().isNotEmpty) {
      return false;
    }

    return isOfflineLoginAvailable();
  }

  // ============================================================
  // CERRAR SESIÓN
  // ============================================================

  Future<void> logOut() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_tokenKey);

    await prefs.remove(_userIdKey);

    await prefs.remove(_empresaIdKey);

    await prefs.remove(_userNameKey);

    await prefs.remove(_companyNameKey);

    await prefs.remove(_roleKey);

    await prefs.remove(_loggedKey);

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
  // ============================================================
  // SNAPSHOT DE LICENCIA
  // ============================================================

  Future<void> saveLicenseSnapshot({
    required String tipo,
    required String? fechaInicio,
    required String? fechaFin,
    required bool activa,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final snapshot = {
      'licencia_tipo': tipo.trim(),
      'licencia_fecha_inicio': fechaInicio?.trim(),
      'licencia_fecha_fin': fechaFin?.trim(),
      'licencia_activa': activa,
      'server_checked_at': DateTime.now().toIso8601String(),
      'received_at': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_licenseSnapshotKey, jsonEncode(snapshot));
  }

  Future<Map<String, dynamic>> getLicenseSnapshot() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_licenseSnapshotKey);

    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    return <String, dynamic>{};
  }

  Future<void> clearLicenseSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseSnapshotKey);
  }

  Future<void> touchLicenseServerCheckedAt() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_licenseSnapshotKey);

    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) return;

      final updated = Map<String, dynamic>.from(decoded);
      updated['server_checked_at'] = DateTime.now().toIso8601String();

      await prefs.setString(_licenseSnapshotKey, jsonEncode(updated));
    } catch (_) {}
  }
  // ============================================================
  // [PASSWORD] requiere_cambio_password
  // ============================================================

  static const String _requiresPasswordChangeKey = 'requires_password_change';

  Future<void> setRequiresPasswordChange(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_requiresPasswordChangeKey, value);
  }

  Future<bool> getRequiresPasswordChange() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_requiresPasswordChangeKey) ?? false;
  }

  Future<void> clearRequiresPasswordChange() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_requiresPasswordChangeKey);
  }

  /// Detecta si el `empresa_id` cambió respecto a la última sesión.
  ///
  /// Devuelve true si cambió y guarda el nuevo empresa_id.
  Future<bool> detectCompanyChange(int newEmpresaId) async {
    final prefs = await SharedPreferences.getInstance();

    final oldEmpresaId = prefs.getInt(_empresaIdKey);

    if (oldEmpresaId == null) {
      // Primera vez: no hay cambio
      return false;
    }

    if (oldEmpresaId == newEmpresaId) {
      return false;
    }

    debugPrint(
      '🔄 Cambio de empresa detectado: '
      '$oldEmpresaId → $newEmpresaId',
    );

    return true;
  }

  /// Limpia SOLO los datos de empresa/usuario pero CONSERVA:
  /// - Credenciales offline
  /// - Últimos IDs online
  /// - Snapshot de licencia
  /// - Configuración del ticket
  ///
  /// Se usa al detectar cambio de empresa.
  Future<void> clearCompanyData() async {
    final prefs = await SharedPreferences.getInstance();

    // Eliminar datos de sesión actual
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_empresaIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_companyNameKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_loggedKey);
    await prefs.remove(_businessDateKey);
    await prefs.remove(_operationStateKey);

    // ⚠️ NO eliminamos:
    // - offline_identifier
    // - offline_password
    // - last_online_user_id
    // - last_online_empresa_id
    // - last_online_at
    // - license_snapshot
    // - ticket_config
  }

  // ============================================================
  // CERRAR SESIÓN PARA LIMPIEZA DE DATOS DEL DÍA
  // ============================================================
  //
  // A diferencia de logOut(), este método:
  //
  //   • Borra TODO lo relacionado a la sesión actual y a la
  //     empresa:
  //       - token
  //       - user_id, empresa_id
  //       - user_name, company_name
  //       - role
  //       - is_logged_in
  //       - server_business_date (fecha comercial)
  //       - operation_state
  //       - requires_password_change
  //       - CREDENCIALES OFFLINE (offline_identifier,
  //         offline_password, offline_day_valid)
  //       - last_online_user_id, last_online_empresa_id,
  //         last_online_at
  //       - catalog_purge_pending
  //
  //   • PRESERVA únicamente:
  //       - license_snapshot (tipo, fechas, activa)
  //       - ticket_config (config global del dispositivo)
  //       - terms_accepted_user_* (consentimiento por titular)
  //
  // Tras esta llamada, cualquier flujo de auto-login offline
  // queda sin datos y la app DEBE mostrar el LoginScreen.
  //
  // Se usa exclusivamente en "Limpiar datos del día".
  Future<void> logOutForCleanup() async {
    final prefs = await SharedPreferences.getInstance();

    // --------------------------------------------------------
    // 1. Sesión activa
    // --------------------------------------------------------
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_empresaIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_companyNameKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_loggedKey);

    // --------------------------------------------------------
    // 2. Fecha comercial y estado operativo
    // --------------------------------------------------------
    await prefs.remove(_businessDateKey);
    await prefs.remove(_operationStateKey);

    // --------------------------------------------------------
    // 3. Marca de cambio de contraseña
    // --------------------------------------------------------
    await prefs.remove(_requiresPasswordChangeKey);

    // --------------------------------------------------------
    // 4. Credenciales offline (evita auto-login)
    // --------------------------------------------------------
    await prefs.remove(_offlineIdentifierKey);
    await prefs.remove(_offlinePasswordKey);
    await prefs.remove(_lastOnlineUserIdKey);
    await prefs.remove(_lastOnlineEmpresaIdKey);
    await prefs.remove(_lastOnlineAtKey);
    await prefs.remove(_offlineDayValidKey);

    // --------------------------------------------------------
    // 5. Purga pendiente de catálogo
    // --------------------------------------------------------
    await prefs.remove(_catalogPurgePendingKey);

    // --------------------------------------------------------
    // 6. NO tocamos:
    // --------------------------------------------------------
    //
    //   • _licenseSnapshotKey   → licencia del dispositivo
    //   • _ticketConfigKey      → config del ticket global
    //   • terms_accepted_user_* → consentimiento T&C
  }
  // ============================================================
  // TÉRMINOS Y CONDICIONES (POR USUARIO)
  // ============================================================
  //
  // El consentimiento de los T&C es POR TITULAR, no por app.
  // Cada usuario que se registra en este dispositivo tiene su
  // propio flag, guardado con la fecha exacta de aceptación.
  //
  // Esto cumple con el principio de consentimiento informado
  // del titular de los datos (no del dispositivo).
  //
  // Se guarda:
  //   terms_accepted_user_{userId}         → bool
  //   terms_accepted_user_{userId}_at      → ISO8601 (auditoría)
  //   terms_accepted_user_{userId}_version → versión del texto

  /// Marca que el usuario indicado aceptó los términos.
  ///
  /// [userId] debe ser > 0. Si es <= 0, la llamada no hace nada.
  Future<void> markTermsAccepted(int userId) async {
    if (userId <= 0) {
      debugPrint('⚠️ markTermsAccepted: userId inválido ($userId)');
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('terms_accepted_user_$userId', true);

    await prefs.setString(
      'terms_accepted_user_${userId}_at',
      DateTime.now().toIso8601String(),
    );

    await prefs.setString(
      'terms_accepted_user_${userId}_version',
      '2026-09-19',
    );
  }

  /// Devuelve true si el usuario indicado ya aceptó los términos
  /// en este dispositivo.
  Future<bool> hasAcceptedTerms(int userId) async {
    if (userId <= 0) return false;

    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool('terms_accepted_user_$userId') ?? false;
  }

  /// Devuelve la fecha en que el usuario aceptó los términos.
  /// Útil para auditoría.
  Future<String?> getTermsAcceptedAt(int userId) async {
    if (userId <= 0) return null;

    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('terms_accepted_user_${userId}_at');
  }

  /// Devuelve la versión del texto que el usuario aceptó.
  Future<String?> getTermsAcceptedVersion(int userId) async {
    if (userId <= 0) return null;

    final prefs = await SharedPreferences.getInstance();

    return prefs.getString('terms_accepted_user_${userId}_version');
  }

  /// Borra la aceptación del usuario indicado.
  ///
  /// Se usa:
  ///   • Al cerrar sesión (opcional, si quieres forzar re-aceptación).
  ///   • Para pruebas manuales.
  ///   • Al actualizar los T&C a una versión que requiere re-aceptación.
  Future<void> clearTermsAccepted(int userId) async {
    if (userId <= 0) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('terms_accepted_user_$userId');
    await prefs.remove('terms_accepted_user_${userId}_at');
    await prefs.remove('terms_accepted_user_${userId}_version');
  }
}
