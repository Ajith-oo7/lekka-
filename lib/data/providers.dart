import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repo.dart';
import 'profile.dart';

const supportedLanguageCodes = ['en', 'te', 'hi'];

/// Set in main.dart once SharedPreferences has loaded.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden in main()'),
);

final authRepoProvider = Provider<AuthRepo>((ref) => AuthRepo(Supabase.instance.client));

/// Emits on every sign-in, sign-out and token refresh.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => Supabase.instance.client.auth.onAuthStateChange,
);

/// The signed-in user, or null.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});

/// The signed-in person's profile row. Reloads when the user changes.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.read(authRepoProvider).fetchMyProfile();
});

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

/// The app language. Saved on the device (shared_preferences) so the first
/// screen opens in the right language, and on the profile so it follows the
/// person to a new phone.
final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class LocaleController extends Notifier<Locale> {
  static const _key = 'language';

  @override
  Locale build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    if (saved != null && supportedLanguageCodes.contains(saved)) return Locale(saved);
    // First launch: use the phone's language if it is Telugu or Hindi.
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return Locale(supportedLanguageCodes.contains(device) ? device : 'en');
  }

  /// Changes the language on this device, and on the profile when signed in.
  Future<void> setLanguage(String code, {bool saveToProfile = true}) async {
    if (!supportedLanguageCodes.contains(code)) return;
    state = Locale(code);
    await ref.read(sharedPrefsProvider).setString(_key, code);
    if (saveToProfile) {
      try {
        await ref.read(authRepoProvider).updateMyLanguage(code);
      } catch (e) {
        // Not fatal: the device copy is saved. Log only in debug, no personal data.
        if (kDebugMode) debugPrint('Could not save language to profile: ${e.runtimeType}');
      }
    }
  }

  /// After sign-in, use the language stored on the profile.
  Future<void> loadFromProfile() async {
    try {
      final profile = await ref.read(authRepoProvider).fetchMyProfile();
      if (profile != null) await setLanguage(profile.language, saveToProfile: false);
    } catch (e) {
      if (kDebugMode) debugPrint('Could not load profile language: ${e.runtimeType}');
    }
  }
}

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// System, light or dark. Kept on the device only.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(_key, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------

/// Which side the home screen shows: money lent or money borrowed.
enum LoanSide { lent, borrowed }

final loanSideProvider = NotifierProvider<LoanSideController, LoanSide>(LoanSideController.new);

class LoanSideController extends Notifier<LoanSide> {
  @override
  LoanSide build() => LoanSide.lent;

  void set(LoanSide side) => state = side;
}
