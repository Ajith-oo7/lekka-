import 'dart:convert';

/// Supabase settings, passed in at build time:
///
///   flutter run --dart-define-from-file=env.json
///
/// env.json holds SUPABASE_URL and SUPABASE_ANON_KEY (see env.example.json).
/// Only the PUBLIC anon key may ever be used here. Never the service-role key.
class AppConfig {
  /// Sent with problem reports. Keep in step with `version:` in pubspec.yaml.
  static const appVersion = '0.6.0';

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Returns null when the settings look usable, otherwise the problem.
  static ConfigProblem? check() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return ConfigProblem.missing;
    }
    if (_looksLikeSecretKey(supabaseAnonKey)) {
      return ConfigProblem.secretKey;
    }
    return null;
  }

  /// Safety net: refuse to start if someone pasted the service-role key.
  /// Older Supabase keys are JWTs with a "role" claim; newer secret keys
  /// start with "sb_secret_".
  static bool _looksLikeSecretKey(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final role = (jsonDecode(payload) as Map<String, dynamic>)['role'];
      return role == 'service_role';
    } catch (_) {
      return false;
    }
  }
}

enum ConfigProblem { missing, secretKey }
