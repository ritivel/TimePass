import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'turnstile_client.dart';

/// Account and cloud-data boundary for the app.
///
/// The URL and publishable key are intentionally compile-time values so no
/// server credential is ever bundled into the client. A build without them is
/// a local-development build and keeps using the on-device cache.
abstract final class ProductBackend {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const authRedirect = String.fromEnvironment(
    'NAKUL_AUTH_REDIRECT',
    defaultValue: 'app.nakul://auth-callback/',
  );
  static const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');
  static const turnstileBaseUrl = String.fromEnvironment(
    'TURNSTILE_BASE_URL',
    defaultValue: 'https://nakul.app',
  );

  static bool _initialized = false;
  static final ValueNotifier<bool> signInRequested = ValueNotifier(false);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && publishableKey.isNotEmpty;

  static bool get isInitialized => _initialized;

  static SupabaseClient get client => Supabase.instance.client;

  static User? get currentUser =>
      isConfigured && _initialized ? client.auth.currentUser : null;

  static String? accessToken() => isConfigured && _initialized
      ? client.auth.currentSession?.accessToken
      : null;

  static bool get isGuest => currentUser?.isAnonymous == true;

  static Future<void> requestExistingAccountSignIn() async {
    signInRequested.value = true;
    if (currentUser != null) await client.auth.signOut();
  }

  static void finishSignInRequest() => signInRequested.value = false;

  static Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    _initialized = true;
  }

  static Future<String?> _captchaToken() async {
    if (turnstileSiteKey.isEmpty) return null;
    try {
      return await TurnstileClient.getToken(
        siteKey: turnstileSiteKey,
        baseUrl: turnstileBaseUrl,
        action: 'nakul_auth',
      );
    } on TurnstileClientException catch (error) {
      throw AuthException('Security check failed: ${error.message}');
    }
  }

  static Future<AuthResponse> signInAnonymously() async {
    return client.auth.signInAnonymously(
      data: const {'onboarding': 'guest_trial'},
      captchaToken: await _captchaToken(),
    );
  }

  static Future<AuthResponse> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    return client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: kIsWeb ? null : authRedirect,
      captchaToken: await _captchaToken(),
    );
  }

  static Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return client.auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: await _captchaToken(),
    );
  }

  static Future<void> resetPasswordForEmail(String email) async {
    return client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : authRedirect,
      captchaToken: await _captchaToken(),
    );
  }

  static Future<List<Map<String, Object?>>> loadConversations() async {
    if (currentUser == null) return const [];
    final rows = await client
        .from('conversations')
        .select('id,title,payload,bookmarked,created_at,updated_at')
        .order('updated_at', ascending: false);
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }

  static Future<void> upsertConversations(
    List<Map<String, Object?>> documents,
  ) async {
    final user = currentUser;
    if (user == null || documents.isEmpty) return;
    await client.from('conversations').upsert([
      for (final document in documents)
        {
          ...document,
          'user_id': user.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
    ], onConflict: 'user_id,id');
  }

  static Future<void> deleteConversation(String id) async {
    if (currentUser == null) return;
    await client.from('conversations').delete().eq('id', id);
  }

  static Future<void> track(
    String name, [
    Map<String, Object?> properties = const {},
  ]) async {
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('product_events').insert({
        'user_id': user.id,
        'name': name,
        'properties': properties,
      });
    } catch (error) {
      // Analytics is deliberately best-effort and must never break answers.
      debugPrint('analytics event failed: $error');
    }
  }
}
