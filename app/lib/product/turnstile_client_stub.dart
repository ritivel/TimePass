final class TurnstileClientException implements Exception {
  const TurnstileClientException(this.message);

  final String message;
}

abstract final class TurnstileClient {
  static Future<String> getToken({
    required String siteKey,
    required String baseUrl,
    required String action,
  }) {
    throw const TurnstileClientException('unsupported platform');
  }
}
