import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/providers.dart';
import 'data/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final problem = AppConfig.check();
  if (problem != null) {
    runApp(ConfigErrorApp(problem: problem));
    return;
  }

  // Public anon key only. Row Level Security in the database decides what
  // each person can see. Supabase debug logging stays off.
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    debug: false,
  );

  // Push notifications. If Firebase is not set up yet the app still runs,
  // just without push (reminders still show on the Reminders screen).
  await PushService.init();

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const LekkaApp(),
  ));
}
