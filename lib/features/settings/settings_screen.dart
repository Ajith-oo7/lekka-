import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/providers.dart';
import '../../data/push_service.dart';
import '../../l10n/app_localizations.dart';
import 'language_picker.dart';

/// Settings: language, theme (system, light, dark), sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = LekkaPalette.of(context);
    final language = ref.watch(localeProvider).languageCode;
    final mode = ref.watch(themeModeProvider);
    final email = ref.watch(currentUserProvider)?.email ?? '';

    final themeOptions = [
      (ThemeMode.system, l.themeSystem, Icons.brightness_auto_outlined),
      (ThemeMode.light, l.themeLight, Icons.light_mode_outlined),
      (ThemeMode.dark, l.themeDark, Icons.dark_mode_outlined),
    ];

    Widget check(bool on) => on ? Icon(Icons.check_circle, color: p.accent) : const SizedBox(width: 24);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: l.settingsLanguage),
          const SizedBox(height: 6),
          LekkaCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (code, label) in languageOptions(l))
                  ListTile(
                    title: Text(label),
                    trailing: check(code == language),
                    selected: code == language,
                    onTap: () => ref.read(localeProvider.notifier).setLanguage(code),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionHeader(title: l.settingsTheme),
          const SizedBox(height: 6),
          LekkaCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (value, label, icon) in themeOptions)
                  ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    trailing: check(value == mode),
                    selected: value == mode,
                    onTap: () => ref.read(themeModeProvider.notifier).setMode(value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LekkaCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l.reportProblem),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(context: context, builder: (_) => const _ReportDialog()),
            ),
          ),
          const SizedBox(height: 20),
          if (email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.signedInAs(email),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout, color: LekkaColors.overdueText),
            label: Text(l.signOut, style: const TextStyle(color: LekkaColors.overdueText)),
            onPressed: () async {
              // The router sends the person back to sign-in when the session ends.
              // Stop push to this phone first, while still signed in.
              final auth = ref.read(authRepoProvider);
              await PushService.unregisterDevice();
              await auth.signOut();
            },
          ),
        ],
      ),
    );
  }
}

/// Report a problem: a short note that goes to the app owner.
class _ReportDialog extends ConsumerStatefulWidget {
  const _ReportDialog();

  @override
  ConsumerState<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<_ReportDialog> {
  final _message = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_message.text.trim().isEmpty) {
      setState(() => _error = l.errorReportEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repoProvider).sendFeedback(_message.text, AppConfig.appVersion);
      messenger.showSnackBar(SnackBar(content: Text(l.reportSent)));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.reportProblem),
      content: TextField(
        controller: _message,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l.reportHint, errorText: _error, errorMaxLines: 3),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(onPressed: _busy ? null : _send, child: Text(l.send)),
      ],
    );
  }
}
