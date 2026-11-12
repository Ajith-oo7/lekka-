import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../settings/language_picker.dart';

/// Sign up / sign in. Name is asked only on sign-up.
/// Changing the language here relabels the form straight away.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

/// Which field a server error belongs under.
enum _ErrorField { email, password, form }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  var _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isSignUp = true;
  bool _busy = false;
  bool _obscure = true;

  /// True once the person taps a language on this screen. On sign-in we then
  /// save their pick to the profile; otherwise we load the profile's language.
  bool _languageTouched = false;

  // Errors that came back from Supabase, shown under the matching field.
  String? _emailError;
  String? _passwordError;
  String? _formError;

  /// Shown after sign-up when Supabase asks the person to confirm their email.
  String? _info;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearServerErrors() {
    _emailError = null;
    _passwordError = null;
    _formError = null;
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _clearServerErrors();
      _info = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    // Read everything from ref now: once sign-in succeeds the router closes
    // this screen, and ref can no longer be used after that.
    final repo = ref.read(authRepoProvider);
    final locale = ref.read(localeProvider.notifier);
    final pickedLanguage = ref.read(localeProvider).languageCode;
    final languageTouched = _languageTouched;
    final email = _email.text.trim();

    try {
      if (_isSignUp) {
        final signedIn = await repo.signUp(
          name: _name.text.trim(),
          email: email,
          password: _password.text,
          language: pickedLanguage,
        );
        if (!signedIn && mounted) {
          // Email confirmation is on in Supabase: ask them to confirm, then sign in.
          setState(() {
            _isSignUp = false;
            _info = l.confirmEmailSent(email);
            _password.clear();
          });
        }
        // If signed in, the router moves to the home screen by itself.
      } else {
        await repo.signIn(email: email, password: _password.text);
        if (languageTouched) {
          await locale.setLanguage(pickedLanguage);
        } else {
          await locale.loadFromProfile();
        }
      }
    } on AuthException catch (e) {
      if (mounted) _showAuthError(e, l);
    } catch (_) {
      if (mounted) setState(() => _formError = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Maps a Supabase Auth error to a translated message under the right field.
  void _showAuthError(AuthException e, AppLocalizations l) {
    final (text, field) = _describe(e, l);
    setState(() {
      switch (field) {
        case _ErrorField.email:
          _emailError = text;
        case _ErrorField.password:
          _passwordError = text;
        case _ErrorField.form:
          _formError = text;
      }
    });
  }

  (String, _ErrorField) _describe(AuthException e, AppLocalizations l) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (e is AuthRetryableFetchException) return (l.errorNetwork, _ErrorField.form);
    if (code == 'invalid_credentials' || msg.contains('invalid login')) {
      return (l.errorWrongCredentials, _ErrorField.password);
    }
    if (code == 'user_already_exists' || code == 'email_exists' || msg.contains('already registered')) {
      return (l.errorEmailInUse, _ErrorField.email);
    }
    if (code == 'weak_password' || msg.contains('password should')) {
      return (l.errorWeakPassword, _ErrorField.password);
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return (l.errorEmailNotConfirmed, _ErrorField.email);
    }
    if (code == 'email_address_invalid' || code == 'validation_failed') {
      return (l.errorEmailInvalid, _ErrorField.email);
    }
    if (code.startsWith('over_') || e.statusCode == '429') {
      return (l.errorTooManyTries, _ErrorField.form);
    }
    return (l.errorGeneric, _ErrorField.form);
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _clearServerErrors();
      _info = null;
      // A new form key clears old field errors but keeps what was typed.
      _formKey = GlobalKey<FormState>();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final language = ref.watch(localeProvider).languageCode;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Center(child: LogoTile(size: 56)),
                    const SizedBox(height: 12),
                    Text(l.appName, style: t.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(l.tagline, style: t.bodyMedium?.copyWith(color: p.muted), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    LekkaCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_isSignUp ? l.signUpTitle : l.signInTitle, style: t.titleLarge),
                            const SizedBox(height: 16),
                            if (_isSignUp) ...[
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.name],
                                decoration: InputDecoration(labelText: l.nameLabel),
                                validator: (v) => (v == null || v.trim().isEmpty) ? l.errorNameRequired : null,
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(labelText: l.emailLabel, errorText: _emailError),
                              onChanged: (_) {
                                if (_emailError != null) setState(() => _emailError = null);
                              },
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                                return ok ? null : l.errorEmailInvalid;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              autofillHints: [_isSignUp ? AutofillHints.newPassword : AutofillHints.password],
                              onFieldSubmitted: (_) => _busy ? null : _submit(),
                              onChanged: (_) {
                                if (_passwordError != null) setState(() => _passwordError = null);
                              },
                              decoration: InputDecoration(
                                labelText: l.passwordLabel,
                                errorText: _passwordError,
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? l.showPassword : l.hidePassword,
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              // Supabase's default minimum is 6 characters.
                              validator: (v) => (v == null || v.length < 6) ? l.errorPasswordShort : null,
                            ),
                            const SizedBox(height: 16),
                            Text(l.languageLabel, style: t.labelMedium?.copyWith(color: p.muted)),
                            const SizedBox(height: 8),
                            LanguageChips(
                              selected: language,
                              onSelected: (code) {
                                _languageTouched = true;
                                // Not signed in yet, so only the device copy is saved here.
                                ref.read(localeProvider.notifier).setLanguage(code, saveToProfile: false);
                              },
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : Text(_isSignUp ? l.signUpButton : l.signInButton),
                            ),
                            if (_formError != null) ...[
                              const SizedBox(height: 10),
                              Text(_formError!, style: t.bodySmall?.copyWith(color: LekkaColors.overdueText)),
                            ],
                            if (_info != null) ...[
                              const SizedBox(height: 10),
                              Text(_info!, style: t.bodyMedium?.copyWith(color: p.accent)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : _toggleMode,
                      child: Text(
                        _isSignUp ? l.switchToSignIn : l.switchToSignUp,
                        textAlign: TextAlign.center,
                      ),
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
