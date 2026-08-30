class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String get apiBaseUrlNormalized {
    return apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }
}
