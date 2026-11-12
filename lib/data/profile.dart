/// A row from the `profiles` table. Created automatically by the database
/// trigger `handle_new_user` when someone signs up.
class Profile {
  const Profile({required this.id, required this.name, required this.language});

  final String id;
  final String name;
  final String language; // 'en', 'te' or 'hi'

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        language: (map['language'] as String?) ?? 'en',
      );
}
