class AppConfig {
  // ============================================================
  // 🔧 Cambia esta URL según tu entorno:
  // - Emulador Android  → http://10.0.2.2:8000
  // - iOS Simulator     → http://127.0.0.1:8000 (funciona)
  // - Dispositivo físico → http://192.168.x.x:8000 (IP de tu PC)
  //defaultValue: 'https://apis.desarrollos-iaeh.org',
  // ============================================================
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://apis.desarrollos-iaeh.org', // <-- Cambia según tu caso
  );

  static const String apiPrefix = '/api/v1';

  static String get apiBaseUrlNormalized {
    return apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  static String endpoint(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$apiBaseUrlNormalized$apiPrefix$cleanPath';
  }
}