import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
    final origin = Uri.tryParse(baseUrl);
    if (origin == null || origin.scheme != 'https' || origin.host.isEmpty) {
      throw const TurnstileClientException(
        'TURNSTILE_BASE_URL must be an HTTPS origin',
      );
    }

    final result = Completer<String>();
    late final HeadlessInAppWebView view;
    view = HeadlessInAppWebView(
      // The plugin default is the full device viewport. A one-pixel headless
      // surface is sufficient for the challenge and avoids allocating a large
      // off-screen render target on memory-constrained Android devices.
      initialSize: const Size(1, 1),
      initialData: InAppWebViewInitialData(
        data: _html(siteKey: siteKey, action: action),
        baseUrl: WebUri(baseUrl),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
        transparentBackground: true,
        disableContextMenu: true,
      ),
      onWebViewCreated: (controller) {
        controller
          ..addJavaScriptHandler(
            handlerName: 'TurnstileToken',
            callback: (arguments) {
              final token = arguments.firstOrNull;
              if (token is String && token.isNotEmpty && !result.isCompleted) {
                result.complete(token);
              }
              return null;
            },
          )
          ..addJavaScriptHandler(
            handlerName: 'TurnstileError',
            callback: (arguments) {
              if (!result.isCompleted) {
                result.completeError(
                  TurnstileClientException(
                    'challenge error ${arguments.firstOrNull ?? 'unknown'}',
                  ),
                );
              }
              return null;
            },
          );
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != false && !result.isCompleted) {
          result.completeError(TurnstileClientException(error.description));
        }
      },
    );

    try {
      await view.run();
      return await result.future.timeout(const Duration(seconds: 20));
    } on TurnstileClientException {
      rethrow;
    } on TimeoutException {
      throw const TurnstileClientException('challenge timed out');
    } on Object catch (error) {
      throw TurnstileClientException('$error');
    } finally {
      try {
        await view.dispose();
      } on Object {
        // The challenge result is more useful than a teardown failure.
      }
    }
  }

  static String _html({required String siteKey, required String action}) =>
      '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"></script>
</head>
<body>
  <div id="challenge"></div>
  <script>
    turnstile.ready(function () {
      turnstile.render('#challenge', {
        sitekey: ${jsonEncode(siteKey)},
        action: ${jsonEncode(action)},
        feedbackEnabled: false,
        callback: function (token) {
          window.flutter_inappwebview.callHandler('TurnstileToken', token);
        },
        'error-callback': function (code) {
          window.flutter_inappwebview.callHandler('TurnstileError', code);
        }
      });
    });
  </script>
</body>
</html>
''';
}
