import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';

final class TurnstileClientException implements Exception {
  const TurnstileClientException(this.message);

  final String message;
}

abstract final class TurnstileClient {
  static Future<String> getToken({
    required String siteKey,
    required String baseUrl,
    required String action,
  }) async {
    final turnstile = CloudflareTurnstile.invisible(
      siteKey: siteKey,
      baseUrl: baseUrl,
      action: action,
    );
    try {
      final token = await turnstile.getToken().timeout(
        const Duration(seconds: 20),
      );
      if (token == null || token.isEmpty) {
        throw const TurnstileClientException(
          'challenge did not return a token',
        );
      }
      return token;
    } on TurnstileClientException {
      rethrow;
    } on TimeoutException {
      throw const TurnstileClientException('challenge timed out');
    } on Object catch (error) {
      throw TurnstileClientException('$error');
    } finally {
      await turnstile.dispose();
    }
  }
}
