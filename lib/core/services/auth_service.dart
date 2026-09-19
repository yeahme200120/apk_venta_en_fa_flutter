import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../services/daily_cleanup_service.dart';
// 🆕 UBICACIÓN
import '../services/location_service.dart';
import '../services/sync_service.dart';
import '../storage/app_storage.dart';
import 'license_service.dart';
import '../database/local_db.dart';
import '../database/pos_db_service.dart';

class AuthService {
  final ApiClient _apiClient;

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  // ============================================================
  // LOGIN
  // ============================================================

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
      final mac = await _deviceIdentifier();

      // 🆕 UBICACIÓN (opcional — no bloquea login si no se puede obtener)
      final location = await LocationService().getCurrentLocation();

      final payload = await _apiClient.login(
        identifier: cleanIdentifier,
        password: password,
        macAddress: mac,
        // 🆕 UBICACIÓN
        latitude: location?.latitude,
        longitude: location?.longitude,
        accuracy: location?.accuracy,
        locationProvider: location?.provider,
      );

      await _saveOnlineSession(payload, cleanIdentifier, password);

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

      final offline = await loginOffline(
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
  }

  // ============================================================
  // REGISTRO
  // ============================================================

  Future<Map<String, dynamic>> register({
    required String empresaNombre,
    required String nombre,
    required String email,
    required String macAddress,
    String? telefono,
    String? rfc,
    // 🆕 UBICACIÓN (opcional)
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationProvider,
  }) async {
    final payload = await _apiClient.register(
      empresaNombre: empresaNombre.trim(),
      nombre: nombre.trim(),
      email: email.trim().toLowerCase(),
      macAddress: macAddress.trim().toUpperCase(),
      telefono: telefono?.trim(),
      rfc: rfc?.trim(),
      // 🆕 UBICACIÓN
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      locationProvider: locationProvider,
    );

    // 🆕 La contraseña ya no la elige el usuario: la genera el
    // backend y viene en `credenciales_iniciales.password_generica`.
    // La usamos para guardar la sesión offline local.
    final credenciales = payload['credenciales_iniciales'] is Map
        ? Map<String, dynamic>.from(payload['credenciales_iniciales'] as Map)
        : <String, dynamic>{};

    final passwordGenerica =
        credenciales['password_generica']?.toString().trim() ?? '';

    await _saveOnlineSession(
      payload,
      email.trim().toLowerCase(),
      passwordGenerica,
    );

    return payload;
  }

  // ============================================================
  // DEVICE IDENTIFIER
  // ============================================================

  Future<String?> _deviceIdentifier() async {
    try {
      final plugin = DeviceInfoPlugin();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await plugin.androidInfo;
        // Android ID (64-bit hex) — persistente hasta factory reset.
        // Android 6+ bloquea la MAC real, así que usamos el ID.
        return androidInfo.id;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await plugin.iosInfo;
        return iosInfo.identifierForVendor ?? iosInfo.name;
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ No se pudo obtener el identificador del dispositivo: $e');
      return null;
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
    final token = (payload['access_token'] ?? payload['token'] ?? '')
        .toString()
        .trim();

    if (token.isEmpty) {
      throw Exception('El servidor no devolvió un token de acceso.');
    }

    final user = payload['user'] is Map
        ? Map<String, dynamic>.from(payload['user'] as Map)
        : <String, dynamic>{};

    final empresa = payload['empresa'] is Map
        ? Map<String, dynamic>.from(payload['empresa'] as Map)
        : <String, dynamic>{};

    final userId = _toInt(user['id'] ?? user['user_id']);

    final companyId = _toInt(empresa['id'] ?? empresa['empresa_id']);

    if (userId <= 0 || companyId <= 0) {
      throw Exception('El servidor devolvió una sesión incompleta.');
    }
    // ==========================================================
    // 🔴 DETECCIÓN DE CAMBIO DE EMPRESA
    // ==========================================================
    final storage = AppStorage();

    final previousCompanyId = await storage.getEmpresaId();

    final companyChanged =
        previousCompanyId != null &&
        previousCompanyId > 0 &&
        previousCompanyId != companyId;

    if (companyChanged) {
      debugPrint(
        '🔄 Cambio de empresa detectado: '
        '$previousCompanyId → $companyId',
      );

      // 1. Sincronizar pendientes de la empresa anterior
      final previousUserId = await storage.getUserId();
      final rawPrevDate = await storage.getServerBusinessDate();
      final prevDate = DateTime.tryParse(rawPrevDate ?? '') ?? DateTime.now();

      if (previousUserId != null && previousUserId > 0) {
        try {
          await SyncService().syncManual(
            companyId: previousCompanyId,
            userId: previousUserId,
            businessDate: prevDate,
          );
        } catch (e) {
          debugPrint('⚠️ Sync antes de cambio de empresa falló: $e');
        }

        // 2. Eliminar la base diaria anterior
        try {
          await PosDatabaseService().deleteDatabaseFile(
            companyId: previousCompanyId,
            userId: previousUserId,
            businessDate: prevDate,
          );
        } catch (e) {
          debugPrint('⚠️ Borrar BD anterior falló: $e');
        }
      }

      // 3. Limpiar TODO el historial local
      try {
        await LocalDb().clearAll();
      } catch (e) {
        debugPrint('⚠️ Limpiar LocalDb falló: $e');
      }
    }
    final serverIdentifier =
        (user['numero_usuario'] ??
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

    final serverBusinessDate = _extractBusinessDate(payload, empresa);

    if (serverBusinessDate == null || serverBusinessDate.trim().isEmpty) {
      throw Exception('El servidor no devolvió la fecha comercial.');
    }

    // ==========================================================
    // 🔴 CAMBIO DE DÍA COMERCIAL
    // ==========================================================

    final dayChanged = await storage.businessDateChanged(serverBusinessDate);

    if (dayChanged) {
      final previousDate = await storage.getServerBusinessDateKey();

      debugPrint(
        '🔄 Cambio de día comercial: '
        '$previousDate → $serverBusinessDate',
      );

      try {
        await _cleanupPreviousBusinessDay(
          companyId: companyId,
          userId: userId,
          previousDate: previousDate,
        );
      } catch (e) {
        debugPrint(
          '⚠️ Cleanup de día anterior falló: $e. '
          'Los pendientes quedan en LocalDb.',
        );
      }
    }

    final userName = (user['name'] ?? user['username'] ?? 'Usuario')
        .toString()
        .trim();

    final companyName = (empresa['nombre'] ?? empresa['name'] ?? '')
        .toString()
        .trim();

    final role = (user['rol'] ?? user['role'] ?? user['tipo_usuario'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    await storage.saveSession(
      token: token,
      userId: userId,
      empresaId: companyId,
      userName: userName,
      isLoggedIn: true,
      offlineIdentifier: serverIdentifier,
      offlinePassword: password,
      serverBusinessDate: serverBusinessDate,
    );

    // ==========================================================
    // [PASSWORD] Guardar el flag de cambio de contraseña requerido.
    //
    // IMPORTANTE:
    // Este bloque está dentro de un try/catch porque el flag es
    // solo informativo para la UI. Si falla su guardado NO debe
    // romper el login ni la sesión recién creada.
    // ==========================================================
    try {
      final requiereCambio =
          user['requiere_cambio_password'] == true ||
          payload['requiere_cambio_password'] == true;

      await storage.setRequiresPasswordChange(requiereCambio);

      debugPrint('🔐 requiere_cambio_password guardado: $requiereCambio');
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar requiere_cambio_password: $e');
    }

    if (companyName.isNotEmpty) {
      await storage.saveCompanyName(companyName);
    }

    if (role.isNotEmpty) {
      await storage.saveRol(role);
    }

    final configuration = empresa['configuracion'];

    if (configuration is Map) {
      final settings = Map<String, dynamic>.from(configuration);

      await storage.saveOperationState({
        'cajas_activas': settings['cajas_activas'] == true,
        'mesas_activas': settings['mesas_activas'] == true,
        'caja_abierta': null,
      });
    }

    // ==========================================================
    // 🔴 SNAPSHOT DE LICENCIA
    // ==========================================================
    try {
      final licencia = payload['licencia'];

      final licenciaMap = licencia is Map
          ? Map<String, dynamic>.from(licencia)
          : <String, dynamic>{};

      final licenciaTipo = (licenciaMap['tipo'] ?? 'prueba').toString().trim();

      final licenciaFechaInicio = licenciaMap['fecha_inicio']?.toString();

      final licenciaFechaFin = licenciaMap['fecha_fin']?.toString();

      final licenciaActiva = licenciaMap['activa'] == true;

      await storage.saveLicenseSnapshot(
        tipo: licenciaTipo.isNotEmpty ? licenciaTipo : 'prueba',
        fechaInicio: licenciaFechaInicio,
        fechaFin: licenciaFechaFin,
        activa: licenciaActiva,
      );

      debugPrint(
        '🔐 Snapshot de licencia guardado: '
        'tipo=$licenciaTipo '
        'fin=$licenciaFechaFin '
        'activa=$licenciaActiva',
      );
    } catch (e) {
      debugPrint('⚠️ No se pudo guardar el snapshot de licencia: $e');
    }

    // ==========================================================
    // 🔴 MARCAR PURGA DE CATÁLOGO
    // ==========================================================
    //
    // Un dispositivo POS se usa con UNA SOLA empresa.
    //
    // Al iniciar sesión online, forzamos que el próximo sync de
    // catálogos purgue productos/categorías/clientes/etc. que
    // pudieran ser de una empresa anterior.
    //
    await storage.markCatalogPurgePending();

    final savedToken = await storage.getToken();

    if (savedToken == null || savedToken.trim().isEmpty) {
      throw Exception('El token no pudo guardarse correctamente.');
    }

    if (savedToken.trim() != token) {
      throw Exception('El token guardado no coincide con el token recibido.');
    }

    final savedUserId = await storage.getUserId();

    final savedCompanyId = await storage.getEmpresaId();

    if (savedUserId != userId || savedCompanyId != companyId) {
      throw Exception('La sesión local no pudo guardarse correctamente.');
    }

    if (!await storage.isOfflineDayValid()) {
      throw Exception('La sesión offline no quedó habilitada correctamente.');
    }
  }

  /// Sincroniza lo pendiente del día anterior, archiva los
  /// pendientes en LocalDb y borra la base diaria vieja.
  ///
  /// Los pendientes que no se pudieron sincronizar quedan en
  /// LocalDb y se reintentarán en cada ciclo de sincronización.
  Future<void> _cleanupPreviousBusinessDay({
    required int companyId,
    required int userId,
    required String? previousDate,
  }) async {
    if (previousDate == null || previousDate.trim().isEmpty) {
      return;
    }

    final previousDateParsed =
        DateTime.tryParse(previousDate) ?? DateTime.now();

    // 1. Intentar sincronizar lo pendiente.
    try {
      await SyncService().syncManual(
        companyId: companyId,
        userId: userId,
        businessDate: previousDateParsed,
      );
    } catch (e) {
      debugPrint(
        '⚠️ Sync del día anterior falló: $e. '
        'Los pendientes quedan en LocalDb.',
      );
    }

    // 2. Archivar pendientes del día a LocalDb (histórico).
    try {
      await SyncService().archivePendingSalesFromDay(
        companyId: companyId,
        userId: userId,
        businessDate: previousDateParsed,
      );
    } catch (e) {
      debugPrint('⚠️ Archivar pendientes falló: $e');
    }

    // 3. Borrar la base diaria vieja.
    try {
      await DailyCleanupService().archiveAndClearDailyDatabase(
        companyId: companyId,
        userId: userId,
        businessDate: previousDateParsed,
      );
    } catch (e) {
      debugPrint('⚠️ Borrar base diaria vieja falló: $e');
    }
  }

  // ============================================================
  // LOGIN OFFLINE
  // ============================================================

  Future<bool> loginOffline({
    required String identifier,
    required String password,
  }) async {
    final cleanIdentifier = identifier.trim();

    if (cleanIdentifier.isEmpty || password.isEmpty) {
      return false;
    }

    final storage = AppStorage();

    final available = await storage.isOfflineLoginAvailable();

    if (!available) {
      return false;
    }

    final savedIdentifier = await storage.getOfflineIdentifier();

    final savedPassword = await storage.getOfflinePassword();

    if (savedIdentifier == null || savedPassword == null) {
      return false;
    }

    if (savedIdentifier.trim() != cleanIdentifier ||
        savedPassword != password) {
      return false;
    }

    final userId = await storage.getLastOnlineUserId();

    final companyId = await storage.getLastOnlineEmpresaId();

    if (userId == null || companyId == null || userId <= 0 || companyId <= 0) {
      return false;
    }

    final businessDate = await storage.getServerBusinessDate();

    if (businessDate == null || businessDate.trim().isEmpty) {
      return false;
    }

    await storage.saveOfflineSession(
      userId: userId,
      empresaId: companyId,
      userName: await storage.getUserName() ?? 'Usuario',
      companyName: await storage.getCompanyName(),
      role: await storage.getRole(),
    );

    final token = await storage.getToken();

    return token == null || token.trim().isEmpty;
  }

  // ============================================================
  // SESIÓN
  // ============================================================

  Future<void> logout() async {
    await LicenseService().clear();
    // [PASSWORD] Limpiar el flag de cambio de contraseña.
    await AppStorage().clearRequiresPasswordChange();
    await AppStorage().logOut();
  }

  Future<bool> hasSession() async {
    final storage = AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final userId = await storage.getUserId();

    final companyId = await storage.getEmpresaId();

    if (userId == null || companyId == null || userId <= 0 || companyId <= 0) {
      await storage.logOut();
      return false;
    }

    final token = await storage.getToken();

    // ----------------------------------------------------------
    // SESIÓN ONLINE
    // ----------------------------------------------------------

    if (token != null && token.trim().isNotEmpty) {
      try {
        final currentUser = await _apiClient.getCurrentUser();

        final serverDate = _extractBusinessDateFromUser(currentUser);

        if (serverDate != null && serverDate.trim().isNotEmpty) {
          final localDate = await storage.getServerBusinessDate();

          if (localDate != null &&
              _normalizeBusinessDate(localDate) !=
                  _normalizeBusinessDate(serverDate)) {
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
    final storage = AppStorage();

    if (!await storage.isLoggedIn()) {
      return false;
    }

    final token = await storage.getToken();

    if (token == null || token.trim().isEmpty) {
      return false;
    }

    try {
      final currentUser = await _apiClient.getCurrentUser();

      final serverDate = _extractBusinessDateFromUser(currentUser);

      if (serverDate != null && serverDate.trim().isNotEmpty) {
        final localDate = await storage.getServerBusinessDate();

        if (localDate != null &&
            _normalizeBusinessDate(localDate) !=
                _normalizeBusinessDate(serverDate)) {
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
    final storage = AppStorage();

    final token = await storage.getToken();

    if (token == null || token.trim().isEmpty) {
      return false;
    }

    try {
      final currentUser = await _apiClient.getCurrentUser();

      final serverDate = _extractBusinessDateFromUser(currentUser);

      if (serverDate == null || serverDate.trim().isEmpty) {
        return false;
      }

      final localDate = await storage.getServerBusinessDate();

      if (localDate == null || localDate.trim().isEmpty) {
        return false;
      }

      return _normalizeBusinessDate(localDate) !=
          _normalizeBusinessDate(serverDate);
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

  Future<String?> getCurrentServerBusinessDate() async {
    try {
      final currentUser = await _apiClient.getCurrentUser();

      return _extractBusinessDateFromUser(currentUser);
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // TOKEN
  // ============================================================

  Future<String?> getToken() async {
    final token = await AppStorage().getToken();

    if (token == null || token.trim().isEmpty) {
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

    return _normalizeBusinessDateValue(rawDate);
  }

  String? _extractBusinessDateFromUser(Map<String, dynamic> payload) {
    final empresa = payload['empresa'] is Map
        ? Map<String, dynamic>.from(payload['empresa'] as Map)
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

    return _normalizeBusinessDateValue(rawDate);
  }

  String? _normalizeBusinessDateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(text);

    return parsed?.toIso8601String() ?? text;
  }

  String _normalizeBusinessDate(String value) {
    final clean = value.trim();

    final parsed = DateTime.tryParse(clean);

    if (parsed != null) {
      return parsed.toIso8601String().substring(0, 10);
    }

    // Si el backend ya entrega YYYY-MM-DD.
    if (clean.length >= 10) {
      return clean.substring(0, 10);
    }

    return clean;
  }

  bool _isNetworkError(Object error) {
    final message = error.toString().toLowerCase();

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

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
