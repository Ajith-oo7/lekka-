import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'loan_providers.dart';
import 'providers.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// The phone's push token is saved in the device_tokens table so the server
/// (Edge Function send-reminders) can reach it. Nothing here shows or logs
/// names or amounts.
///
/// Firebase needs the platform files from the Firebase console
/// (google-services.json for Android, GoogleService-Info.plist for iPhone;
/// see the README). Until they are added, [ready] stays false and the app
/// simply runs without push.
class PushService {
  static bool ready = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      ready = true;
    } catch (e) {
      ready = false;
      if (kDebugMode) debugPrint('Push is off: Firebase is not set up (${e.runtimeType})');
    }
  }

  /// Asks for permission, then saves this phone's token for the signed-in person.
  static Future<void> registerDevice() async {
    if (!ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken();
      if (token == null) return;
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Could not register for push: ${e.runtimeType}');
    }
  }

  /// Removes this phone's token. Call before signing out.
  static Future<void> unregisterDevice() async {
    if (!ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client.from('device_tokens').delete().eq('token', token);
    } catch (e) {
      if (kDebugMode) debugPrint('Could not unregister push: ${e.runtimeType}');
    }
  }
}

/// While someone is signed in: keep this phone registered, and refresh the
/// Reminders list when a push arrives with the app open.
final pushSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null || !PushService.ready) return;

  PushService.registerDevice();
  final subscriptions = <StreamSubscription<dynamic>>[
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => PushService.registerDevice()),
    FirebaseMessaging.onMessage.listen((_) => ref.invalidate(notificationsProvider)),
    FirebaseMessaging.onMessageOpenedApp.listen((_) => ref.invalidate(notificationsProvider)),
  ];
  ref.onDispose(() {
    for (final s in subscriptions) {
      s.cancel();
    }
  });
});
