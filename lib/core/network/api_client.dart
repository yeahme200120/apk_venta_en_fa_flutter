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
          final token = await AppStorage().getToken();

          print('🔑 Token obtenido: $token');

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
            print('🔒 Header Authorization agregado');
          } else {
            print('⚠️ Token vacío o nulo');
          }

          print(
            '🌐 URL completa: ${options.baseUrl}${options.path}',
          );

          handler.next(options);
        },
        onResponse: (response, handler) {
          print(
            '📡 Respuesta: ${response.statusCode} - ${response.data}',
          );

          if (response.statusCode == 401) {
            AppStorage().logOut();
          }

          handler.next(response);
        },
        onError: (DioException error, handler) async {
          print('❌ Error en API: ${error.message}');
          print('❌ Código: ${error.response?.statusCode}');
          print('❌ Data: ${error.response?.data}');

          if (error.response?.statusCode == 401) {
            await AppStorage().logOut();
          }

          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  // ============================================================
  // ERROR DE API
  // ============================================================

  static String parseApiError(
    dynamic payload, {
    String fallback = 'Ocurrió un error.',
  }) {
    if (payload is Map) {
      final message = payload['message'] ??
          payload['error'] ??
          payload['detail'];

      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }

      final errors = payload['errors'];

      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;

        if (first is List && first.isNotEmpty) {
          return first.first.toString();
        }

        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
    }

    if (payload is String && payload.trim().isNotEmpty) {
      return payload.trim();
    }

    return fallback;
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/login',
        data: {
          'identificador': identifier,
          'password': password,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
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
          fallback: 'Error de autenticación',
        ),
      );
    }
  }

  // ============================================================
  // USUARIO ACTUAL
  // ============================================================

  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _dio.get(
        '/api/v1/user',
      );

      if (response.statusCode == 200 && response.data is Map) {
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

  // ============================================================
  // ACTUALIZAR PERFIL
  // ============================================================

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _dio.patch(
        '/api/v1/user/profile',
        data: payload,
      );

      if (response.statusCode == 200 && response.data is Map) {
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

  // ============================================================
  // CAMBIAR CONTRASEÑA
  // ============================================================

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

  // ============================================================
  // OLVIDÉ MI CONTRASEÑA
  // ============================================================

  Future<Map<String, dynamic>> forgotPassword({
    required String email,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/forgot',
        data: {
          'email': email,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
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

  // ============================================================
  // RESTABLECER CONTRASEÑA
  // ============================================================

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/reset',
        data: {
          'email': email,
          'token': token,
          'password': password,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
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
          fallback: 'No se pudo restablecer la contraseña',
        ),
      );
    }
  }

  // ============================================================
  // PERMISOS
  // ============================================================

  Future<Map<String, dynamic>> getPermissions() async {
    try {
      final response = await _dio.get(
        '/api/v1/me/permissions',
      );

      if (response.statusCode == 200 && response.data is Map) {
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

      if (response.statusCode == 200 && response.data is Map) {
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

      if (response.statusCode == 200 && response.data is Map) {
        final data = (response.data as Map)['data'];

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
        if (notes != null && notes.trim().isNotEmpty)
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
        if (notes != null && notes.trim().isNotEmpty)
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
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();
      }

      return const [];
    } on DioException catch (e) {
      throw Exception(
        parseApiError(
          e.response?.data,
          fallback: 'No se pudieron consultar las mesas',
        ),
      );
    }
  }

  // ============================================================
  // GUARDAR MESA
  // ============================================================

  Future<Map<String, dynamic>> saveTable({
    int? id,
    required String name,
    int? capacity,
    String? notes,
    bool? active,
  }) {
    final payload = <String, dynamic>{
      'nombre': name.trim(),
      if (capacity != null) 'capacidad': capacity,
      if (notes != null && notes.trim().isNotEmpty)
        'notas': notes.trim(),
      if (active != null) 'activo': active,
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
  // POST GENÉRICO
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
          fallback: 'No se pudo completar la operación',
        ),
      );
    }
  }

  // ============================================================
  // PUT GENÉRICO
  // ============================================================

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
          fallback: 'No se pudo completar la operación',
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
        queryParameters: desde == null
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
          fallback: 'No se pudo descargar el catálogo',
        ),
      );
    }
  }

  // ============================================================
  // SYNC OFFLINE
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

  // ============================================================
  // SYNC PULL
  // ============================================================

  Future<Map<String, dynamic>> syncPull({
    String? cursor,
  }) async {
    try {
      final response = await _dio.get(
        '/api/v1/sync/pull',
        queryParameters: cursor == null
            ? null
            : {
                'cursor': cursor,
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
          fallback: 'No se pudieron obtener los cambios',
        ),
      );
    }
  }

  // ============================================================
  // SYNC GENERAL
  // ============================================================

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
          fallback: 'No se pudo completar la sincronización',
        ),
      );
    }
  }

  // ============================================================
  // CREAR VENTA ONLINE
  // ============================================================

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
          fallback: 'No se pudo sincronizar la venta',
        ),
      );
    }
  }

  // ============================================================
  // DEVOLVER VENTA
  // ============================================================

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
          fallback: 'No se pudo procesar la devolución',
        ),
      );
    }
  }

  // ============================================================
  // ANULAR VENTA
  // ============================================================

  Future<Map<String, dynamic>> cancelSale(
    int saleId, {
    String? reason,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/ventas/$saleId/anular',
        data: {
          if (reason != null && reason.trim().isNotEmpty)
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
          fallback: 'No se pudo cancelar la venta',
        ),
      );
    }
  }

  // ============================================================
  // CONFIGURACIÓN DE EMPRESA
  // ============================================================

  Future<Map<String, dynamic>> getCompanyConfig() async {
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

  Future<Map<String, dynamic>> updateCompanyConfig(
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

  Future<Map<String, dynamic>> getTicketConfig() async {
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

  Future<Map<String, dynamic>> updateTicketConfig(
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

  Future<Map<String, dynamic>> shareDailyReport(
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
          fallback: 'No se pudo compartir el reporte',
        ),
      );
    }
  }
}