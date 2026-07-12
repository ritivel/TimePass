import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/tp_theme.dart';
import 'legal_screen.dart';
import 'product_backend.dart';

const _googleAuthEnabled = bool.fromEnvironment('GOOGLE_AUTH_ENABLED');

class AuthGate extends StatefulWidget {
  const AuthGate({required this.signedInBuilder, super.key});

  final WidgetBuilder signedInBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  bool _recoveringPassword = false;
  bool _startingGuest = false;
  String? _guestError;

  @override
  void initState() {
    super.initState();
    _session = ProductBackend.client.auth.currentSession;
    ProductBackend.signInRequested.addListener(_signInRequestChanged);
    _subscription = ProductBackend.client.auth.onAuthStateChange.listen(
      (state) {
        if (!mounted) return;
        setState(() {
          _session = state.session;
          _recoveringPassword = state.event == AuthChangeEvent.passwordRecovery;
        });
        if (state.session?.user.isAnonymous == false) {
          ProductBackend.finishSignInRequest();
        } else if (state.session == null &&
            !ProductBackend.signInRequested.value) {
          unawaited(_startGuest());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('auth session update failed: $error');
      },
    );
    if (_session == null) unawaited(_startGuest());
  }

  void _signInRequestChanged() {
    if (!mounted) return;
    setState(() {});
    if (!ProductBackend.signInRequested.value && _session == null) {
      unawaited(_startGuest());
    }
  }

  Future<void> _startGuest() async {
    if (_startingGuest || ProductBackend.signInRequested.value) return;
    setState(() {
      _startingGuest = true;
      _guestError = null;
    });
    try {
      final response = await ProductBackend.signInAnonymously();
      if (mounted) setState(() => _session = response.session);
    } on AuthException catch (error) {
      if (mounted) setState(() => _guestError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _guestError = 'Could not start Nakul. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _startingGuest = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    ProductBackend.signInRequested.removeListener(_signInRequestChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recoveringPassword) {
      return _PasswordRecoveryScreen(
        onComplete: () => setState(() => _recoveringPassword = false),
      );
    }
    if (_session?.user != null) return widget.signedInBuilder(context);
    if (ProductBackend.signInRequested.value) return const _AuthScreen();
    return _GuestStartScreen(
      busy: _startingGuest,
      error: _guestError,
      onRetry: _startGuest,
      onSignIn: () => ProductBackend.signInRequested.value = true,
    );
  }
}

class _GuestStartScreen extends StatelessWidget {
  const _GuestStartScreen({
    required this.busy,
    required this.error,
    required this.onRetry,
    required this.onSignIn,
  });

  final bool busy;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 42, color: context.tp.ink),
              const SizedBox(height: 20),
              Text(
                error ?? 'Preparing Nakul…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (busy) ...[
                const SizedBox(height: 20),
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(
                  onPressed: onSignIn,
                  child: const Text('I already have an account'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showGuestUpgradeSheet(
  BuildContext context, {
  required Future<void> Function() onExistingAccount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.tp.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _GuestUpgradeSheet(onExistingAccount: onExistingAccount),
  );
}

class _GuestUpgradeSheet extends StatefulWidget {
  const _GuestUpgradeSheet({required this.onExistingAccount});

  final Future<void> Function() onExistingAccount;

  @override
  State<_GuestUpgradeSheet> createState() => _GuestUpgradeSheetState();
}

class _GuestUpgradeSheetState extends State<_GuestUpgradeSheet> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _linkGoogle() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ProductBackend.client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : ProductBackend.authRedirect,
      );
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkEmail() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _isError = true;
        _message = 'Enter a valid email address.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ProductBackend.client.auth.updateUser(
        UserAttributes(email: email),
        emailRedirectTo: kIsWeb ? null : ProductBackend.authRedirect,
      );
      if (mounted) {
        setState(() {
          _isError = false;
          _message =
              'Check your email to finish saving your account. Your chats stay here; set a password from Account afterward.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _existingAccount() async {
    setState(() => _busy = true);
    try {
      await widget.onExistingAccount();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final t = context.tp;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.cloud_done_outlined, size: 42, color: t.ink),
          const SizedBox(height: 16),
          Text(
            'Keep your chats',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'You’ve used your five free questions. Create an account to keep asking and sync everything across devices.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 24),
          if (_googleAuthEnabled) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _linkGoogle,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('Continue with Google'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or use email',
                    style: TextStyle(color: t.inkMuted),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            onSubmitted: (_) => _busy ? null : _linkEmail(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _linkEmail,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save with email'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isError ? t.signalRed : t.signalGreen,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _existingAccount,
            child: const Text('I already have an account'),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class _AuthScreen extends StatefulWidget {
  const _AuthScreen();

  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 8) {
      setState(() {
        _isError = true;
        _message =
            'Enter a valid email and a password of at least 8 characters.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_signUp) {
        final response = await ProductBackend.signUpWithPassword(
          email: email,
          password: password,
        );
        if (response.session == null && mounted) {
          setState(() {
            _isError = false;
            _message = 'Check your email to confirm your account.';
          });
        }
      } else {
        await ProductBackend.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = 'Could not reach Nakul. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ProductBackend.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : ProductBackend.authRedirect,
      );
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _isError = true;
        _message = 'Enter your email first.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await ProductBackend.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _isError = false;
          _message = 'Password reset link sent. Check your email.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _isError = true;
          _message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.ink,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: t.onAction,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _signUp ? 'Create your Nakul account' : 'Welcome back',
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 30,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your chats, saved answers and preferences stay private and sync across your devices.',
                      style: TextStyle(color: t.inkMuted, height: 1.45),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: [
                        _signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => _busy ? null : _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _isError ? t.signalRed : t.signalGreen,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: t.ink,
                        foregroundColor: t.onAction,
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                    if (!_signUp)
                      TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Forgot password?'),
                      ),
                    const SizedBox(height: 4),
                    if (_googleAuthEnabled) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _google,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _signUp = !_signUp;
                              _message = null;
                            }),
                      child: Text(
                        _signUp
                            ? 'Already have an account? Sign in'
                            : 'New to Nakul? Create an account',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : ProductBackend.finishSignInRequest,
                      child: const Text('Continue as guest'),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'By continuing, you agree to our ',
                          style: TextStyle(color: t.inkMuted, fontSize: 12),
                        ),
                        _LegalLink(
                          label: 'Terms',
                          document: LegalDocument.terms,
                        ),
                        Text(
                          ' and ',
                          style: TextStyle(color: t.inkMuted, fontSize: 12),
                        ),
                        _LegalLink(
                          label: 'Privacy Policy',
                          document: LegalDocument.privacy,
                        ),
                        Text(
                          '.',
                          style: TextStyle(color: t.inkMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.document});

  final String label;
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LegalScreen(document: document),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PasswordRecoveryScreen extends StatefulWidget {
  const _PasswordRecoveryScreen({required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<_PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ProductBackend.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      widget.onComplete();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: context.tp.signalRed)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Update password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
