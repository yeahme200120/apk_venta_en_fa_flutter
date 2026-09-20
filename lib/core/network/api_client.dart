import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../services/location_service.dart';
import '../storage/app_storage.dart';

import 'package:flutter/foundation.dart';

// ============================================================
// AUTENTICACIÓN
// ============================================================
//
// CAMBIO AUTH:
// Excepción tipada para que SyncService pueda distinguir una
// sesión expirada de cualquier otro error de red/API.
//
// NO contiene token ni información sensible.
//
class AuthenticationException implements Exception {
  const AuthenticationException([
    this.message = 'La sesión ha expirado. Inicia sesión nuevamente.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient()
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrlNormalized,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final token = await AppStorage().getToken();

            if (token != null && token.trim().isNotEmpty) {
              options.headers['Authorization'] = 'Bearer ${token.trim()}';
            }
          } catch (e) {
            debugPrint('[API] Error obteniendo token: $e');
          }

          // ============================================================
          // 🆕 UBICACIÓN AUTOMÁTICA
          // ============================================================
          //
          // Inyecta la última ubicación conocida en cada petición
          // POST / PUT / PATCH que:
          //   • tenga un body tipo Map.
          //   • NO traiga ya su propia latitud/longitud.
          //
          // Esto cubre:
          //   • updateProfile
          //   • changePassword
          //   • updateCompanyConfig
          //   • updateTicketConfig
          //   • saveTable
          //   • createProduct / updateProduct
          //   • createCategory / updateCategory
          //   • syncOffline
          //   • openCashRegister / closeCashRegister
          //   • registerCashMovement
          //   • cancelSale / returnSale
          //   • shareDailyReport
          //   • uploadCompanyLogo (multipart)
          //   • etc.
          //
          // NO inyecta en GET (no tiene body).
          // Si no hay ubicación cacheada, no envía nada.
          // Si el método ya la envía explícitamente, se respeta.
          //
          final method = options.method.toUpperCase();
          final metodoConBody =
              method == 'POST' || method == 'PUT' || method == 'PATCH';

          if (metodoConBody) {
            final data = options.data;

            if (data is Map) {
              final tieneUbicacion =
                  data.containsKey('latitud') || data.containsKey('longitud');

              if (!tieneUbicacion) {
                final cached = LocationService.lastKnown;

                if (cached != null) {
                  data['latitud'] = cached.latitude;
                  data['longitud'] = cached.longitude;
                  data['precision_metros'] = cached.accuracy;

                  if (cached.provider.trim().isNotEmpty) {
                    data['ubicacion_provider'] = cached.provider;
                  }
                }
              }
            }
          }

          debugPrint(
            '[API] ${options.method} ${options.uri} '
            'token=${options.headers['Authorization'] != null}',
          );

          handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[API] ${response.requestOptions.method} '
            '${response.requestOptions.uri} '
            '-> ${response.statusCode}',
          );

          handler.next(response);
        },
        onError: (error, handler) async {
          debugPrint(
            '[API] ERROR ${error.requestOptions.method} '
            '${error.requestOptions.uri} '
            '-> ${error.response?.statusCode}',
          );

          if (error.response?.statusCode == 401) {
            await AppStorage().logOut();
          }

          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  Dio get dio => _dio;

  // ============================================================
  // CACHÉ Y DEDUPLICACIÓN DE ESTADO OPERATIVO Y MESAS
  // ============================================================
  //
  // Evita peticiones duplicadas cuando varios widgets del
  // HomeShell piden el mismo recurso al mismo tiempo durante
  // el arranque (IndexedStack monta todos los tabs a la vez).
  //
  // El estado operativo se cachea 5s (cambia con frecuencia).
  // Las mesas se cachean 10s (cambian con menos frecuencia).
  //
  // Además, se deduplican peticiones concurrentes: si ya hay
  // una petición en vuelo al mismo endpoint, las siguientes
  // esperan esa misma promesa en lugar de lanzar otra.
  //
  // Para forzar datos frescos tras una operación que cambia
  // el estado (abrir/cerrar caja, guardar mesa), se debe llamar
  // a `invalidateOperationCache()`.

  Map<String, dynamic>? _cachedOperationStatus;
  DateTime? _cachedOperationStatusAt;
  static const Duration _operationStatusTtl = Duration(seconds: 5);

  /// Petición en vuelo de `/operacion/estado`.
  /// Evita que múltiples widgets que piden el estado al mismo
  /// tiempo disparen múltiples peticiones HTTP en paralelo.
  Future<Map<String, dynamic>>? _operationStatusInFlight;

  List<Map<String, dynamic>>? _cachedTables;
  DateTime? _cachedTablesAt;
  static const Duration _tablesTtl = Duration(seconds: 10);

  /// Petición en vuelo de `/mesas`.
  Future<List<Map<String, dynamic>>>? _tablesInFlight;

  /// Invalida las cachés de operación y mesas.
  ///
  /// Llamar después de abrir/cerrar caja, guardar mesa,
  /// o cualquier operación que cambie el estado operativo.
  ///
  /// No se tocan las peticiones en vuelo (_operationStatusInFlight
  /// ni _tablesInFlight): esas se completarán solas y actualizarán
  /// la caché cuando llegue la respuesta.
  void invalidateOperationCache() {
    _cachedOperationStatus = null;
    _cachedOperationStatusAt = null;
    _cachedTables = null;
    _cachedTablesAt = null;
  }

  // ============================================================
  // MANEJO CENTRALIZADO DE ERRORES
  // ============================================================

  static String parseApiError(
    dynamic payload, {
    String fallback = 'Ocurrió un error.',
  }) {
    if (payload is Map) {
      final errors = payload['errors'];

      if (errors is Map && errors.isNotEmpty) {
        final messages = <String>[];

        for (final entry in errors.entries) {
          final value = entry.value;

          if (value is List) {
            for (final item in value) {
              if (item != null && item.toString().trim().isNotEmpty) {
                messages.add(item.toString().trim());
              }
            }
          } else if (value != null && value.toString().trim().isNotEmpty) {
            messages.add(value.toString().trim());
          }
        }

        if (messages.isNotEmpty) {
          return messages.join('\n');
        }
      }

      final message =
          payload['message'] ?? payload['error'] ?? payload['detail'];

      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    if (payload is String && payload.trim().isNotEmpty) {
      return payload.trim();
    }

    return fallback;
  }

  Never _throwDioError(DioException error, {required String fallback}) {
    final message = parseApiError(error.response?.data, fallback: fallback);

    if (error.response?.statusCode == 401) {
      throw AuthenticationException(
        message.isNotEmpty
            ? message
            : 'La sesión ha expirado. Inicia sesión nuevamente.',
      );
    }

    throw DioException(
      requestOptions: error.requestOptions,
      response: error.response,
      type: error.type,
      error: message,
      stackTrace: error.stackTrace,
      message: message,
    );
  }

  // ============================================================
  // AUTENTICACIÓN
  // ============================================================

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
    String? macAddress,
    // 🆕 UBICACIÓN (opcional)
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationProvider,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/login',
        data: {
          'identificador': identifier.trim(),
          'password': password,
          if (macAddress != null && macAddress.trim().isNotEmpty)
            'mac_address': macAddress.trim().toUpperCase(),

          'latitud': ?latitude,
          'longitud': ?longitude,
          'precision_metros': ?accuracy,
          'ubicacion_provider': ?locationProvider,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del servidor');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'Error de autenticación');
    }
  }

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
    // ✅ T&C
    required bool terminosAceptados,
    required String terminosVersion,
  }) async {
    try {
      debugPrint(
        '[REGISTER] body = ${{'empresa_nombre': empresaNombre, 'terminos_aceptados': terminosAceptados, 'terminos_version': terminosVersion}}',
      );
      final response = await _dio.post(
        '/api/v1/register',
        data: {
          'empresa_nombre': empresaNombre.trim(),
          'nombre': nombre.trim(),
          'email': email.trim().toLowerCase(),
          'mac_address': macAddress.trim().toUpperCase(),
          if (telefono != null && telefono.trim().isNotEmpty)
            'telefono': telefono.trim(),
          if (rfc != null && rfc.trim().isNotEmpty) 'rfc': rfc.trim(),

          // 🆕 UBICACIÓN
          'latitud': ?latitude,
          'longitud': ?longitude,
          'precision_metros': ?accuracy,
          'ubicacion_provider': ?locationProvider,
          // ✅ T&C — OBLIGATORIOS
          'terminos_aceptados': terminosAceptados, // bool → true
          'terminos_version': terminosVersion, // string → '2026-09-19'
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del servidor');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo completar el registro');
    }
  }

  Future<bool> checkEmailAvailable(String email) async {
    try {
      final response = await _dio.post(
        '/api/v1/register/check-email',
        data: {'email': email.trim().toLowerCase()},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return response.data['disponible'] == true;
      }

      return false;
    } on DioException {
      return false;
    }
  }

  Future<bool> checkEmpresaAvailable(String empresaNombre) async {
    try {
      final response = await _dio.post(
        '/api/v1/register/check-empresa',
        data: {'empresa_nombre': empresaNombre.trim()},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return response.data['disponible'] == true;
      }

      return false;
    } on DioException {
      return false;
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _dio.get('/api/v1/user');

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo cargar el usuario');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo cargar el perfil');
    }
  }

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.patch('/api/v1/user/profile', data: payload);

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo actualizar el perfil');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo actualizar el perfil');
    }
  }

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/user/password',
        data: {
          'password_actual': currentPassword,
          'password_nueva': newPassword,
          'password_nueva_confirmation': newPassword,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo cambiar la contraseña');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo cambiar la contraseña');
    }
  }

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/forgot',
        data: {'email': email.trim()},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo solicitar el restablecimiento');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo recuperar la contraseña');
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/reset',
        data: {'email': email.trim(), 'token': token, 'password': password},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo restablecer la contraseña');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo recuperar la contraseña');
    }
  }

  Future<Map<String, dynamic>> getPermissions() async {
    try {
      final response = await _dio.get('/api/v1/me/permissions');

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudieron cargar los permisos');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudieron cargar los permisos');
    }
  }

  // ============================================================
  // ESTADO OPERATIVO
  // ============================================================
  //
  // Caché con TTL 5s + deduplicación de peticiones en vuelo.
  // HomeShell, OperationScreen y otros widgets piden el
  // estado al mismo tiempo al montar el IndexedStack.

  Future<Map<String, dynamic>> getOperationStatus() async {
    final now = DateTime.now();

    // 1. Cache hit.
    if (_cachedOperationStatus != null &&
        _cachedOperationStatusAt != null &&
        now.difference(_cachedOperationStatusAt!) < _operationStatusTtl) {
      debugPrint('ℹ️ OperationStatus desde cache (TTL 5s)');
      return _cachedOperationStatus!;
    }

    // 2. Ya hay una petición en vuelo → esperarla.
    if (_operationStatusInFlight != null) {
      debugPrint('ℹ️ OperationStatus deduplicado (petición en vuelo)');
      return _operationStatusInFlight!;
    }

    // 3. Lanzar nueva petición.
    _operationStatusInFlight = _fetchOperationStatus(now);

    try {
      return await _operationStatusInFlight!;
    } finally {
      _operationStatusInFlight = null;
    }
  }

  Future<Map<String, dynamic>> _fetchOperationStatus(DateTime now) async {
    try {
      final response = await _dio.get('/api/v1/operacion/estado');

      if (response.statusCode == 200 && response.data is Map) {
        final payload = Map<String, dynamic>.from(response.data as Map);
        final data = payload['data'];
        final result = data is Map ? Map<String, dynamic>.from(data) : payload;

        _cachedOperationStatus = result;
        _cachedOperationStatusAt = now;

        return result;
      }

      throw Exception('No se pudo consultar el estado operativo');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo consultar el estado operativo');
    }
  }

  // ============================================================
  // CAJA ACTUAL
  // ============================================================

  Future<Map<String, dynamic>?> getCurrentCashRegister() async {
    try {
      final response = await _dio.get('/api/v1/cajas/actual');

      if (response.statusCode == 200 && response.data is Map) {
        final data = (response.data as Map)['data'];

        return data is Map ? Map<String, dynamic>.from(data) : null;
      }

      throw Exception('No se pudo consultar la caja actual');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo consultar la caja actual');
    }
  }

  // ============================================================
  // OPERACIONES DE CAJA
  // ============================================================

  Future<List<Map<String, dynamic>>> getCashOperations({
    int? cashRegisterId,
    DateTime? date,
  }) async {
    final queryParameters = <String, dynamic>{};

    if (cashRegisterId != null) {
      queryParameters['caja_id'] = cashRegisterId;
    }

    if (date != null) {
      queryParameters['fecha'] = date.toIso8601String();
    }

    Future<Response<dynamic>> request(String path) {
      return _dio.get(
        path,
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );
    }

    Response<dynamic> response;

    try {
      response = await request('/api/v1/cajas/operaciones');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        response = await request('/api/v1/caja/operaciones');
      } else {
        _throwDioError(
          e,
          fallback: 'No se pudieron consultar las operaciones de caja',
        );
      }
    }

    if (response.statusCode != 200) {
      throw Exception('No se pudieron consultar las operaciones de caja');
    }

    dynamic payload = response.data;

    if (payload is Map) {
      payload =
          payload['data'] ??
          payload['operaciones'] ??
          payload['movimientos'] ??
          payload;
    }

    if (payload is Map) {
      payload =
          payload['data'] ??
          payload['operaciones'] ??
          payload['movimientos'] ??
          payload;
    }

    if (payload is! List) {
      return const [];
    }

    return payload
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  // ============================================================
  // ABRIR CAJA
  // ============================================================

  Future<Map<String, dynamic>> openCashRegister({
    required double openingAmount,
    String? notes,
    bool forzarReapertura = false,
    // 🆕 UBICACIÓN (opcional)
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationProvider,
  }) async {
    final result = await _postOperation('/api/v1/cajas/abrir', {
      'monto_apertura': openingAmount,
      if (notes != null && notes.trim().isNotEmpty) 'notas': notes.trim(),
      if (forzarReapertura) 'forzar_reapertura': true,

      // 🆕 UBICACIÓN
      'latitud': ?latitude,
      'longitud': ?longitude,
      'precision_metros': ?accuracy,
      'ubicacion_provider': ?locationProvider,
    });

    // 🔑 El estado operativo cambió (hay caja abierta).
    invalidateOperationCache();

    return result;
  }

  // ============================================================
  // CERRAR CAJA
  // ============================================================

  Future<Map<String, dynamic>> closeCashRegister({
    required int cashRegisterId,
    required double declaredAmount,
    String? notes,
    // 🆕 UBICACIÓN (opcional)
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationProvider,
  }) async {
    final result =
        await _postOperation('/api/v1/cajas/$cashRegisterId/cerrar', {
      'monto_cierre_declarado': declaredAmount,
      if (notes != null && notes.trim().isNotEmpty) 'notas': notes.trim(),

      // 🆕 UBICACIÓN
      'latitud': ?latitude,
      'longitud': ?longitude,
      'precision_metros': ?accuracy,
      'ubicacion_provider': ?locationProvider,
    });

    // 🔑 El estado operativo cambió (caja cerrada).
    invalidateOperationCache();

    return result;
  }

  // ============================================================
  // MESAS
  // ============================================================
  //
  // Caché con TTL 10s + deduplicación de peticiones en vuelo.
  // PosScreen y OperationScreen piden mesas al montar.

  Future<List<Map<String, dynamic>>> getTables() async {
    final now = DateTime.now();

    // 1. Cache hit.
    if (_cachedTables != null &&
        _cachedTablesAt != null &&
        now.difference(_cachedTablesAt!) < _tablesTtl) {
      debugPrint('ℹ️ Mesas desde cache (TTL 10s)');
      return _cachedTables!;
    }

    // 2. Ya hay una petición en vuelo → esperarla.
    if (_tablesInFlight != null) {
      debugPrint('ℹ️ Mesas deduplicadas (petición en vuelo)');
      return _tablesInFlight!;
    }

    // 3. Lanzar nueva petición.
    _tablesInFlight = _fetchTables(now);

    try {
      return await _tablesInFlight!;
    } finally {
      _tablesInFlight = null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTables(DateTime now) async {
    try {
      final response = await _dio.get('/api/v1/mesas');

      final data = response.data is Map ? (response.data as Map)['data'] : null;

      if (data is List) {
        final result = data
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        _cachedTables = result;
        _cachedTablesAt = now;

        return result;
      }

      return const [];
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudieron consultar las mesas');
    }
  }

  Future<Map<String, dynamic>> saveTable({
    int? id,
    required String name,
    int? capacity,
    String? notes,
    bool? active,
  }) async {
    final payload = <String, dynamic>{
      'nombre': name.trim(),
      'capacidad': ?capacity,
      'notas': ?(notes != null && notes.trim().isNotEmpty
          ? notes.trim()
          : null),
      'activo': ?active,
    };

    final result = id == null
        ? await _postOperation('/api/v1/mesas', payload)
        : await _putOperation('/api/v1/mesas/$id', payload);

    // 🔑 Las mesas cambiaron.
    invalidateOperationCache();

    return result;
  }

  // ============================================================
  // OPERACIONES HTTP COMUNES
  // ============================================================

  Future<Map<String, dynamic>> _postOperation(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(path, data: payload);

      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del servidor');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo completar la operación');
    }
  }

  Future<Map<String, dynamic>> _putOperation(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put(path, data: payload);

      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del servidor');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo completar la operación');
    }
  }

  // ============================================================
  // ESTADÍSTICAS DEL MES
  // ============================================================

  Future<Map<String, dynamic>> getMonthStats({
    int? year,
    int? month,
    String? fecha,
    DateTime? date,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    try {
      final queryParameters = <String, dynamic>{};

      if (year != null) {
        queryParameters['year'] = year;
      }

      if (month != null) {
        queryParameters['month'] = month;
      }

      if (fecha != null && fecha.trim().isNotEmpty) {
        queryParameters['fecha'] = fecha.trim();
      }

      if (date != null) {
        queryParameters['fecha'] = date.toIso8601String();
      }

      if (desde != null) {
        queryParameters['desde'] = desde.toIso8601String();
      }

      if (hasta != null) {
        queryParameters['hasta'] = hasta.toIso8601String();
      }

      final response = await _dio.get(
        '/api/v1/estadisticas/mes',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudieron obtener las estadísticas del mes');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudieron obtener las estadísticas del mes',
      );
    }
  }

  // ============================================================
  // CATEGORÍAS
  // ============================================================

  Future<Map<String, dynamic>> createCategory(
    Map<String, dynamic> payload,
  ) async {
    return _postOperation('/api/v1/categorias', payload);
  }

  Future<Map<String, dynamic>> updateCategory(
    int serverId,
    Map<String, dynamic> payload,
  ) async {
    return _putOperation('/api/v1/categorias/$serverId', payload);
  }

  // ============================================================
  // PRODUCTOS
  // ============================================================

  Future<Map<String, dynamic>> createProduct(
    Map<String, dynamic> payload,
  ) async {
    return _postOperation('/api/v1/productos', payload);
  }

  Future<Map<String, dynamic>> updateProduct(
    int serverId,
    Map<String, dynamic> payload,
  ) async {
    return _putOperation('/api/v1/productos/$serverId', payload);
  }

  Future<Map<String, dynamic>> getCatalog({String? desde}) async {
    try {
      final response = await _dio.get(
        '/api/v1/catalogos',
        queryParameters: desde == null ? null : {'desde': desde},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del catálogo');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo descargar el catálogo');
    }
  }

  Future<Map<String, dynamic>> getCatalogs({DateTime? desde}) async {
    return getCatalog(desde: desde?.toIso8601String());
  }

  // ============================================================
  // SINCRONIZACIÓN OFFLINE
  // ============================================================

  Future<Map<String, dynamic>> syncOffline(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/sync/offline', data: payload);

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo sincronizar la venta fuera de línea');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo sincronizar la venta fuera de línea',
      );
    }
  }

  Future<Map<String, dynamic>> syncPull({String? cursor}) async {
    try {
      final response = await _dio.get(
        '/api/v1/sync/pull',
        queryParameters: cursor == null || cursor.trim().isEmpty
            ? null
            : {'cursor': cursor.trim()},
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudieron obtener los cambios');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudieron obtener los cambios');
    }
  }

  Future<Map<String, dynamic>> sync(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/sync', data: payload);

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo completar la sincronización');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo completar la sincronización');
    }
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/ventas', data: payload);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo sincronizar la venta');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo sincronizar la venta');
    }
  }

  Future<Map<String, dynamic>> returnSale(
    int saleId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/ventas/$saleId/devolver',
        data: payload,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo procesar la devolución');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo procesar la devolución');
    }
  }

  Future<Map<String, dynamic>> cancelSale(int saleId, {String? reason}) async {
    try {
      final response = await _dio.post(
        '/api/v1/ventas/$saleId/anular',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'motivo': reason.trim(),
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo cancelar la venta');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo cancelar la venta');
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE EMPRESA
  // ============================================================

  Future<Map<String, dynamic>> getCompanyConfig() async {
    try {
      final response = await _dio.get('/api/v1/admin/empresa/config');

      if (response.statusCode == 200 && response.data is Map) {
        debugPrint('[COMPANY CONFIG] response.data = ${response.data}');

        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo cargar la configuración de empresa');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo cargar la configuración de empresa',
      );
    }
  }

  Future<Map<String, dynamic>> updateCompanyConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put(
        '/api/v1/admin/empresa/config',
        data: payload,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo actualizar la configuración de empresa');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo actualizar la configuración de empresa',
      );
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE TICKET
  // ============================================================

  Future<Map<String, dynamic>> getTicketConfig() async {
    try {
      final response = await _dio.get('/api/v1/ticket/config');

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo cargar la configuración del ticket');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo cargar la configuración del ticket',
      );
    }
  }

  Future<Map<String, dynamic>> updateTicketConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put('/api/v1/ticket/config', data: payload);

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo actualizar la configuración del ticket');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo actualizar la configuración del ticket',
      );
    }
  }

  // ============================================================
  // COMPARTIR REPORTE DIARIO
  // ============================================================

  Future<Map<String, dynamic>> shareDailyReport(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/reports/daily/share',
        data: payload,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo compartir el reporte');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo compartir el reporte');
    }
  }

  Future<Map<String, dynamic>> getCompanyLogo() async {
    try {
      final response = await _dio.get('/api/v1/empresa/logo');

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo obtener el logo de la empresa');
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo obtener el logo de la empresa');
    }
  }

  Future<List<int>?> downloadCompanyLogo({String? logoUrl}) async {
    final normalizedUrl = logoUrl?.trim();

    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return null;
    }

    try {
      final response = await _dio.get<List<int>>(
        normalizedUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == 200 &&
          response.data != null &&
          response.data!.isNotEmpty) {
        return response.data!;
      }

      return null;
    } on DioException catch (e) {
      _throwDioError(e, fallback: 'No se pudo descargar el logo de la empresa');
    }
  }

  Future<Map<String, dynamic>> uploadCompanyLogo(File logoFile) async {
    try {
      if (!await logoFile.exists()) {
        throw Exception('El archivo del logo no existe.');
      }

      final formData = FormData.fromMap({
        'logo': await MultipartFile.fromFile(
          logoFile.path,
          filename: 'logo.webp',
        ),
      });

      final response = await _dio.post(
        '/api/v1/empresa/logo',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('No se pudo actualizar el logo de la empresa');
    } on DioException catch (e) {
      _throwDioError(
        e,
        fallback: 'No se pudo actualizar el logo de la empresa',
      );
    }
  }

  // ============================================================
  // REGISTRAR MOVIMIENTO DE CAJA
  // ============================================================

  Future<Map<String, dynamic>> registerCashMovement({
    int? cashRegisterId,
    required String tipo,
    required String concepto,
    required double monto,
    String? referencia,
    String? notas,
    String? formaPago,
    // 🆕 UBICACIÓN (opcional)
    double? latitude,
    double? longitude,
    double? accuracy,
    String? locationProvider,
  }) async {
    final path = cashRegisterId != null && cashRegisterId > 0
        ? '/api/v1/cajas/$cashRegisterId/movimientos'
        : '/api/v1/cajas/movimientos';

    return _postOperation(path, {
      'tipo': tipo,
      'concepto': concepto.trim(),
      'monto': monto,
      if (referencia != null && referencia.trim().isNotEmpty)
        'referencia': referencia.trim(),
      if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
      if (formaPago != null && formaPago.trim().isNotEmpty)
        'forma_pago': formaPago.trim(),

      // 🆕 UBICACIÓN
      'latitud': ?latitude,
      'longitud': ?longitude,
      'precision_metros': ?accuracy,
      'ubicacion_provider': ?locationProvider,
    });
  }
}