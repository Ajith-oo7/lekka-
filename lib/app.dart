import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'data/loan_providers.dart';
import 'data/providers.dart';
import 'data/push_service.dart';
import 'features/auth/auth_screen.dart';
import 'features/chits/chits_screen.dart';
import 'features/groups/group_detail_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/home/home_shell.dart';
import 'features/invite/join_screen.dart';
import 'features/home/loans_screen.dart';
import 'features/loans/change_terms_screen.dart';
import 'features/loans/loan_detail_screen.dart';
import 'features/loans/new_loan_screen.dart';
import 'features/records/records_screen.dart';
import 'features/reminders/reminders_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/summary/summary_screen.dart';
import 'l10n/app_localizations.dart';

/// Tells go_router to re-check its redirect whenever the person signs in or out.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(GoTrueClient auth) {
    _sub = auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// An invite code that arrived by link before the person was signed in.
/// Used once, right after sign-in.
String? _pendingInviteCode;

/// Reads the code out of an invite link: lekka://join/CODE or /join/CODE.
String? _inviteCodeFrom(Uri uri) {
  final parts = uri.pathSegments;
  if (uri.host == 'join' && parts.isNotEmpty) return parts.first;
  if (parts.length == 2 && parts.first == 'join') return parts[1];
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;
  final refresh = _AuthRefresh(auth);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.loans,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atAuth = state.matchedLocation == Routes.auth;
      final inviteCode = _inviteCodeFrom(state.uri);
      if (!signedIn) {
        if (inviteCode != null) _pendingInviteCode = inviteCode;
        return atAuth ? null : Routes.auth;
      }
      if (atAuth) {
        final code = _pendingInviteCode;
        _pendingInviteCode = null;
        return code == null ? Routes.loans : Routes.joinWith(code);
      }
      // A custom-scheme link (lekka://join/CODE) puts "join" in the host.
      if (state.uri.host == 'join' && inviteCode != null) return Routes.joinWith(inviteCode);
      return null;
    },
    routes: [
      GoRoute(path: Routes.auth, builder: (context, state) => const AuthScreen()),
      GoRoute(path: Routes.chits, builder: (context, state) => const ChitsScreen()),
      GoRoute(path: Routes.settings, builder: (context, state) => const SettingsScreen()),
      GoRoute(path: Routes.groups, builder: (context, state) => const GroupsScreen()),
      GoRoute(
        path: Routes.groupPattern,
        builder: (context, state) => GroupDetailScreen(groupId: state.pathParameters['id']!),
      ),
      // '/loan/new' is listed before '/loan/:id' so "new" is never read as an id.
      GoRoute(
        path: Routes.newLoanPattern,
        builder: (context, state) => NewLoanScreen(
          groupId: state.uri.queryParameters['group'],
          iAmBorrower: state.uri.queryParameters['side'] == 'borrowed',
        ),
      ),
      GoRoute(path: Routes.join, builder: (context, state) => const JoinScreen()),
      GoRoute(
        path: Routes.joinPattern,
        builder: (context, state) => JoinScreen(initialCode: state.pathParameters['code']),
      ),
      GoRoute(
        path: Routes.changeTermsPattern,
        builder: (context, state) => ChangeTermsScreen(loanId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.loanPattern,
        builder: (context, state) => LoanDetailScreen(loanId: state.pathParameters['id']!),
      ),
      // The four bottom-bar tabs. Each keeps its own scroll position.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.loans, builder: (context, state) => const LoansScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.records, builder: (context, state) => const RecordsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.reminders, builder: (context, state) => const RemindersScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.summary, builder: (context, state) => const SummaryScreen()),
          ]),
        ],
      ),
    ],
  );
});

/// The app: theme, router and localization.
class LekkaApp extends ConsumerWidget {
  const LekkaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    ref.watch(realtimeSyncProvider); // keeps shared loans in step between phones
    ref.watch(pushSyncProvider); // registers this phone for push while signed in
    final lang = locale.languageCode;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      theme: buildLekkaTheme(Brightness.light, lang),
      darkTheme: buildLekkaTheme(Brightness.dark, lang),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      // Very large phone font sizes are capped at 1.4× so amounts and buttons
      // stay readable without breaking the layout.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.4,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Shown instead of the app when env.json is missing or holds a secret key.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problem});

  final ConfigProblem problem;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLekkaTheme(Brightness.light, 'en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        final l = AppLocalizations.of(context);
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  problem == ConfigProblem.missing ? l.configMissing : l.configSecretKey,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
