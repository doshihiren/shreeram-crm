class ApiConfig {
  /// Override at build time:
  /// `--dart-define=API_BASE_URL=https://aweliontech.com/shreeram-crm/api/v1`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://aweliontech.com/shreeram-crm/api/v1',
  );
}
