import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/app_storage.dart';

class ApiClient {
  ApiClient() : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrlNormalized,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 20),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await AppStorage().getToken();
          if ((token ?? '').isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 401) {
            await AppStorage().logOut();
          }
          handler.next(response);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            await AppStorage().logOut();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;

  static String parseApiError(dynamic payload, {String fallback = 'Ocurrió un error.'}) {
    if (payload is Map) {
      final message = payload['message'] ?? payload['error'] ?? payload['detail'];
      if (message is String && message.trim().isNotEmpty) return message;

      final errors = payload['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first is String && first.isNotEmpty) return first;
      }
    }

    if (payload is String && payload.trim().isNotEmpty) {
      return payload;
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
          'identificador': identifier,
          'password': password,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      throw Exception('Respuesta inválida del servidor');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'Error de autenticación'));
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
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo cargar el perfil'));
    }
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.patch('/api/v1/user/profile', data: payload);
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo actualizar el perfil');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo actualizar el perfil'));
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
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo cambiar la contraseña'));
    }
  }

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    try {
      final response = await _dio.post(
        '/api/v1/password/forgot',
        data: {'email': email},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo solicitar el restablecimiento');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo recuperar la contraseña'));
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
          'email': email,
          'token': token,
          'password': password,
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo restablecer la contraseña');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo restablecer la contraseña'));
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
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudieron cargar los permisos'));
    }
  }

  Future<List<Map<String, dynamic>>> getCatalog({String? desde}) async {
    try {
      final response = await _dio.get(
        '/api/v1/catalogos',
        queryParameters: desde == null ? null : {'desde': desde},
      );

      if (response.statusCode == 200) {
        final raw = response.data;
        if (raw is List) {
          return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        }
        if (raw is Map && raw['data'] is List) {
          return (raw['data'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
        if (raw is Map && raw['productos'] is List) {
          return (raw['productos'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }

      return const [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await AppStorage().logOut();
      }
      return const [];
    }
  }

  Future<Map<String, dynamic>> syncOffline(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/sync/offline', data: payload);
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo sincronizar la venta fuera de línea');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo sincronizar la venta fuera de línea'));
    }
  }

  Future<Map<String, dynamic>> syncPull({String? cursor}) async {
    try {
      final response = await _dio.get(
        '/api/v1/sync/pull',
        queryParameters: cursor == null ? null : {'cursor': cursor},
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudieron obtener los cambios');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudieron obtener los cambios'));
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
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo completar la sincronización'));
    }
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> payload) async {
    final response = await _dio.post('/api/v1/ventas', data: payload);

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    }

    throw Exception('No se pudo sincronizar la venta');
  }

  Future<Map<String, dynamic>> returnSale(int saleId, Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/ventas/$saleId/devolver', data: payload);
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo procesar la devolución');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo procesar la devolución'));
    }
  }

  Future<Map<String, dynamic>> cancelSale(int saleId, {String? reason}) async {
    try {
      final response = await _dio.post('/api/v1/ventas/$saleId/anular', data: {'motivo': reason});
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo cancelar la venta');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo cancelar la venta'));
    }
  }

  Future<Map<String, dynamic>> getCompanyConfig() async {
    final response = await _dio.get('/api/v1/admin/empresa/config');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateCompanyConfig(Map<String, dynamic> payload) async {
    final response = await _dio.put('/api/v1/admin/empresa/config', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> getTicketConfig() async {
    final response = await _dio.get('/api/v1/ticket/config');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateTicketConfig(Map<String, dynamic> payload) async {
    final response = await _dio.put('/api/v1/ticket/config', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> shareDailyReport(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post('/api/v1/reports/daily/share', data: payload);
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
      throw Exception('No se pudo compartir el reporte');
    } on DioException catch (e) {
      throw Exception(parseApiError(e.response?.data, fallback: 'No se pudo compartir el reporte'));
    }
  }
}
