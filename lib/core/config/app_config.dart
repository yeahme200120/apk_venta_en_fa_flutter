class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://apis.desarrollos-iaeh.org',
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