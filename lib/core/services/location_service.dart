import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ============================================================
// MODELO DE UBICACIÓN
// ============================================================

class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.provider,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Precisión en metros. Menor = mejor.
  final double accuracy;

  /// "gps", "network", "unknown"
  final String provider;

  final DateTime timestamp;

  Map<String, dynamic> toMap() => {
    'latitud': latitude,
    'longitud': longitude,
    'precision_metros': accuracy,
    'ubicacion_provider': provider,
  };

  @override
  String toString() =>
      'DeviceLocation($latitude, $longitude, '
      '${accuracy.toStringAsFixed(1)}m, $provider)';
}

// ============================================================
// SERVICIO
// ============================================================

class LocationService {
  LocationService._internal();

  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  // ============================================================
  // CONFIGURACIÓN
  // ============================================================

  /// Precisión máxima aceptable en metros.
  ///
  /// Si la ubicación obtenida tiene `accuracy > _maxAccuracy`,
  /// se descarta y se devuelve `null`.
  static const double _maxAccuracy = 100.0;

  /// Tiempo máximo de espera por una ubicación.
  static const Duration _timeout = Duration(seconds: 3);

  /// Duración del cache en memoria.
  static const Duration _cacheTtl = Duration(minutes: 5);

  // ============================================================
  // CACHE EN MEMORIA
  // ============================================================

  DeviceLocation? _cached;
  DateTime? _cachedAt;

  // ============================================================
  // API PÚBLICA
  // ============================================================

  /// Verifica si el servicio de ubicación está habilitado.
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('⚠️ Error verificando servicio de ubicación: $e');
      return false;
    }
  }

  /// Verifica el estado actual del permiso.
  Future<LocationPermission> checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (e) {
      debugPrint('⚠️ Error verificando permiso: $e');
      return LocationPermission.denied;
    }
  }

  /// Solicita el permiso al usuario.
  Future<LocationPermission> requestPermission() async {
    try {
      return await Geolocator.requestPermission();
    } catch (e) {
      debugPrint('⚠️ Error solicitando permiso: $e');
      return LocationPermission.denied;
    }
  }

  /// Obtiene la ubicación actual.
  ///
  /// Devuelve `null` si:
  ///   - El servicio está deshabilitado.
  ///   - El permiso fue denegado.
  ///   - No se pudo obtener una ubicación con precisión aceptable.
  ///   - Ocurrió un timeout.
  ///
  /// Si `useCache` es `true` y hay una ubicación cacheada
  /// reciente (< 5 min), la devuelve directamente.
  Future<DeviceLocation?> getCurrentLocation({
    bool useCache = true,
    Duration timeout = _timeout,
    double minAccuracy = _maxAccuracy,
  }) async {
    // Cache.
    if (useCache && _isCacheValid()) {
      debugPrint('📍 Usando ubicación en cache.');
      return _cached;
    }

    try {
      // 1. Servicio habilitado.
      final enabled = await isLocationServiceEnabled();

      if (!enabled) {
        debugPrint('📍 Servicio de ubicación deshabilitado.');
        return null;
      }

      // 2. Permisos.
      var permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('📍 Permiso de ubicación denegado.');
        return null;
      }

      // 3. Obtener posición con doble timeout:
      //    a) LocationSettings.timeLimit → límite nativo de Android.
      //    b) .timeout() de Dart → seguro adicional si el nativo
      //       se queda colgado (bug conocido de geolocator en
      //       algunos dispositivos/emuladores).
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      ).timeout(timeout);

      // 4. Validar precisión.
      if (position.accuracy > minAccuracy) {
        debugPrint(
          '📍 Ubicación descartada por baja precisión: '
          '${position.accuracy.toStringAsFixed(1)}m > '
          '${minAccuracy.toStringAsFixed(1)}m',
        );
        return null;
      }

      final location = DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        provider: _providerFromAccuracy(position.accuracy),
        timestamp: DateTime.now(),
      );

      _cached = location;
      _cachedAt = DateTime.now();

      debugPrint('📍 Ubicación obtenida: $location');

      return location;
    } on TimeoutException {
      debugPrint('📍 Timeout obteniendo ubicación.');
      return null;
    } catch (e) {
      debugPrint('📍 Error obteniendo ubicación: $e');
      return null;
    }
  }

  /// Limpia el cache en memoria.
  void clearCache() {
    _cached = null;
    _cachedAt = null;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  bool _isCacheValid() {
    if (_cached == null || _cachedAt == null) return false;

    final age = DateTime.now().difference(_cachedAt!);
    return age < _cacheTtl;
  }

  /// geolocator no expone el provider directamente.
  /// Usamos la precisión como heurística.
  String _providerFromAccuracy(double accuracy) {
    if (accuracy <= 15) return 'gps';
    if (accuracy <= 50) return 'gps';
    if (accuracy <= 150) return 'network';
    return 'unknown';
  }
}
