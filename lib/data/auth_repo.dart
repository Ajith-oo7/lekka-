import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile.dart';

/// Sign-up, sign-in and the person's own profile row.
///
/// Passwords go straight to Supabase Auth. They are never stored or logged here.
class AuthRepo {
  AuthRepo(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  /// Creates the account. Name and language travel as user metadata; the
  /// database trigger copies them into the new `profiles` row.
  ///
  /// Returns true when the person is signed in straight away, false when
  /// Supabase is set to ask them to confirm their email first.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required String language,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name, 'language': language},
    );
    return res.session != null;
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// The signed-in person's profile, or null if not signed in / not found.
  Future<Profile?> fetchMyProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('id, name, language')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  /// Saves the language choice on the profile (RLS lets a person edit only their own row).
  Future<void> updateMyLanguage(String language) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('profiles').update({'language': language}).eq('id', user.id);
  }
}
