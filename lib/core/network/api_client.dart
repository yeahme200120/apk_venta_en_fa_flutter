import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/app_storage.dart';

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
              options.headers['Authorization'] =
                  'Bearer ${token.trim()}';
            }
          } catch (e) {
            print('[API] Error obteniendo token: $e');
          }

          print(
            '[API] ${options.method} ${options.uri} '
            'token=${options.headers['Authorization'] != null}',
          );

          handler.next(options);
        },
        onResponse: (response, handler) {
          print(
            '[API] ${response.requestOptions.method} '
            '${response.requestOptions.uri} '
            '-> ${response.statusCode}',
          );

          handler.next(response);
        },
        onError: (error, handler) async {
          print(
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
              if (item != null &&
                  item.toString().trim().isNotEmpty) {
                messages.add(item.toString().trim());
              }
            }
          } else if (value != null &&
              value.toString().trim().isNotEmpty) {
            messages.add(value.toString().trim());
          }
        }

        if (messages.isNotEmpty) {
          return messages.join('\n');
        }
      }

      final message =
          payload['message'] ??
          payload['error'] ??
          payload['detail'];

      if (message is String &&
          message.trim().isNotEmpty) {
        return message.trim();
      }
    }

    if (payload is String &&
        payload.trim().isNotEmpty) {
      return payload.trim();
    }

    return fallback;
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/login',
        data: {
          'identificador': identifier.trim(),
          'password': password,
        },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Respuesta inválida del servidor',
      );
    } on DioException catch (e) {
      final message = parseApiError(
        e.response?.data,
        fallback: 'Error de autenticación',
      );

      throw Exception(message);
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _dio.get(
        '/api/v1/user',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo cargar el usuario',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo cargar el perfil',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.patch(
        '/api/v1/user/profile',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo actualizar el perfil',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo actualizar el perfil',
        ),
      );
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

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo cambiar la contraseña',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo cambiar la contraseña',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/forgot',
        data: {
          'email': email.trim(),
        },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo solicitar el restablecimiento',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo recuperar la contraseña',
        ),
      );
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
        data: {
          'email': email.trim(),
          'token': token,
          'password': password,
        },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo restablecer la contraseña',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo recuperar la contraseña',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> getPermissions() async {
    try {
      final response = await _dio.get(
        '/api/v1/me/permissions',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudieron cargar los permisos',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudieron cargar los permisos',
        ),
      );
    }
  }

  // ============================================================
  // ESTADO OPERATIVO
  // ============================================================

  Future<Map<String, dynamic>> getOperationStatus() async {
    try {
      final response = await _dio.get(
        '/api/v1/operacion/estado',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        final payload = Map<String, dynamic>.from(
          response.data as Map,
        );

        final data = payload['data'];

        return data is Map
            ? Map<String, dynamic>.from(data)
            : payload;
      }

      throw Exception(
        'No se pudo consultar el estado operativo',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo consultar el estado operativo',
        ),
      );
    }
  }

  // ============================================================
  // CAJA ACTUAL
  // ============================================================

  Future<Map<String, dynamic>?> getCurrentCashRegister() async {
    try {
      final response = await _dio.get(
        '/api/v1/cajas/actual',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        final data =
            (response.data as Map)['data'];

        return data is Map
            ? Map<String, dynamic>.from(data)
            : null;
      }

      throw Exception(
        'No se pudo consultar la caja actual',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudo consultar la caja actual',
        ),
      );
    }
  }

  // ============================================================
  // OPERACIONES DE CAJA
  // ============================================================

  Future<List<Map<String, dynamic>>>
      getCashOperations({
    int? cashRegisterId,
    DateTime? date,
  }) async {
    final queryParameters =
        <String, dynamic>{};

    if (cashRegisterId != null) {
      queryParameters['caja_id'] =
          cashRegisterId;
    }

    if (date != null) {
      queryParameters['fecha'] =
          date.toIso8601String();
    }

    Future<Response<dynamic>> request(
      String path,
    ) {
      return _dio.get(
        path,
        queryParameters:
            queryParameters.isEmpty
                ? null
                : queryParameters,
      );
    }

    Response<dynamic> response;

    try {
      response = await request(
        '/api/v1/cajas/operaciones',
      );
    } on DioException catch (e) {
      // Algunas versiones del backend exponen la ruta singular.
      if (e.response?.statusCode == 404) {
        response = await request(
          '/api/v1/caja/operaciones',
        );
      } else {
        throw Exception(
          parseApiError(
            e.response?.data,
            fallback:
                'No se pudieron consultar las operaciones de caja',
          ),
        );
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudieron consultar las operaciones de caja',
      );
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
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  // ============================================================
  // ABRIR CAJA
  // ============================================================

  Future<Map<String, dynamic>> openCashRegister({
    required double openingAmount,
    String? notes,
  }) async {
    return _postOperation(
      '/api/v1/cajas/abrir',
      {
        'monto_apertura': openingAmount,
        if (notes != null &&
            notes.trim().isNotEmpty)
          'notas': notes.trim(),
      },
    );
  }

  // ============================================================
  // CERRAR CAJA
  // ============================================================

  Future<Map<String, dynamic>> closeCashRegister({
    required int cashRegisterId,
    required double declaredAmount,
    String? notes,
  }) async {
    return _postOperation(
      '/api/v1/cajas/$cashRegisterId/cerrar',
      {
        'monto_cierre_declarado': declaredAmount,
        if (notes != null &&
            notes.trim().isNotEmpty)
          'notas': notes.trim(),
      },
    );
  }

  // ============================================================
  // MESAS
  // ============================================================

  Future<List<Map<String, dynamic>>> getTables() async {
    try {
      final response = await _dio.get(
        '/api/v1/mesas',
      );

      final data = response.data is Map
          ? (response.data as Map)['data']
          : null;

      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (item) => Map<String, dynamic>.from(
                item,
              ),
            )
            .toList();
      }

      return const [];
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudieron consultar las mesas',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> saveTable({
    int? id,
    required String name,
    int? capacity,
    String? notes,
    bool? active,
  }) {
    final payload =
        <String, dynamic>{
      'nombre': name.trim(),
      if (capacity != null)
        'capacidad': capacity,
      if (notes != null &&
          notes.trim().isNotEmpty)
        'notas': notes.trim(),
      if (active != null)
        'activo': active,
    };

    if (id == null) {
      return _postOperation(
        '/api/v1/mesas',
        payload,
      );
    }

    return _putOperation(
      '/api/v1/mesas/$id',
      payload,
    );
  }

  // ============================================================
  // OPERACIONES HTTP COMUNES
  // ============================================================

  Future<Map<String, dynamic>> _postOperation(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        path,
        data: payload,
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Respuesta inválida del servidor',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo completar la operación',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _putOperation(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put(
        path,
        data: payload,
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Respuesta inválida del servidor',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo completar la operación',
        ),
      );
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
      final queryParameters =
          <String, dynamic>{};

      if (year != null) {
        queryParameters['year'] = year;
      }

      if (month != null) {
        queryParameters['month'] = month;
      }

      if (fecha != null &&
          fecha.trim().isNotEmpty) {
        queryParameters['fecha'] =
            fecha.trim();
      }

      if (date != null) {
        queryParameters['fecha'] =
            date.toIso8601String();
      }

      if (desde != null) {
        queryParameters['desde'] =
            desde.toIso8601String();
      }

      if (hasta != null) {
        queryParameters['hasta'] =
            hasta.toIso8601String();
      }

      final response = await _dio.get(
        '/api/v1/estadisticas/mes',
        queryParameters:
            queryParameters.isEmpty
                ? null
                : queryParameters,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudieron obtener las estadísticas del mes',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudieron obtener las estadísticas del mes',
        ),
      );
    }
  }

  // ============================================================
  // CATÁLOGO
  // ============================================================

  Future<Map<String, dynamic>> getCatalog({
    String? desde,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/catalogos',
        queryParameters:
            desde == null
                ? null
                : {
                    'desde': desde,
                  },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Respuesta inválida del catálogo',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await AppStorage().logOut();
      }

      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo descargar el catálogo',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> getCatalogs({
    DateTime? desde,
  }) async {
    return getCatalog(
      desde:
          desde?.toIso8601String(),
    );
  }

  // ============================================================
  // SINCRONIZACIÓN OFFLINE
  // ============================================================

  Future<Map<String, dynamic>> syncOffline(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/sync/offline',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo sincronizar la venta fuera de línea',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo sincronizar la venta fuera de línea',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> syncPull({
    String? cursor,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/sync/pull',
        queryParameters:
            cursor == null ||
                    cursor.trim().isEmpty
                ? null
                : {
                    'cursor':
                        cursor.trim(),
                  },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudieron obtener los cambios',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudieron obtener los cambios',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> sync(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/sync',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo completar la sincronización',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo completar la sincronización',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> createSale(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/ventas',
        data: payload,
      );

      if ((response.statusCode == 200 ||
              response.statusCode == 201) &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo sincronizar la venta',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo sincronizar la venta',
        ),
      );
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

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo procesar la devolución',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo procesar la devolución',
        ),
      );
    }
  }

  Future<Map<String, dynamic>> cancelSale(
    int saleId, {
    String? reason,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/ventas/$saleId/anular',
        data: {
          if (reason != null &&
              reason.trim().isNotEmpty)
            'motivo': reason.trim(),
        },
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo cancelar la venta',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo cancelar la venta',
        ),
      );
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE EMPRESA
  // ============================================================

  Future<Map<String, dynamic>>
      getCompanyConfig() async {
    try {
      final response = await _dio.get(
        '/api/v1/admin/empresa/config',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo cargar la configuración de empresa',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo cargar la configuración de empresa',
        ),
      );
    }
  }

  Future<Map<String, dynamic>>
      updateCompanyConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put(
        '/api/v1/admin/empresa/config',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo actualizar la configuración de empresa',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo actualizar la configuración de empresa',
        ),
      );
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE TICKET
  // ============================================================

  Future<Map<String, dynamic>>
      getTicketConfig() async {
    try {
      final response = await _dio.get(
        '/api/v1/ticket/config',
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo cargar la configuración del ticket',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo cargar la configuración del ticket',
        ),
      );
    }
  }

  Future<Map<String, dynamic>>
      updateTicketConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.put(
        '/api/v1/ticket/config',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo actualizar la configuración del ticket',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo actualizar la configuración del ticket',
        ),
      );
    }
  }

  // ============================================================
  // COMPARTIR REPORTE DIARIO
  // ============================================================

  Future<Map<String, dynamic>>
      shareDailyReport(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.post(
        '/api/v1/reports/daily/share',
        data: payload,
      );

      if (response.statusCode == 200 &&
          response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'No se pudo compartir el reporte',
      );
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback:
              'No se pudo compartir el reporte',
        ),
      );
    }
  }
}
