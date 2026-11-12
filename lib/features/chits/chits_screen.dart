import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../home/lekka_app_bar.dart';

/// Chits placeholder: an icon, the word "Chits" and "Coming soon". Nothing else.
class ChitsScreen extends StatelessWidget {
  const ChitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);

    // The phone's back button returns to Loans instead of closing the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.loans);
      },
      child: Scaffold(
      appBar: const LekkaAppBar(section: TopSection.chits),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.tint,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.tintBorder),
                ),
                child: Icon(Icons.groups_outlined, size: 34, color: p.accent),
              ),
              const SizedBox(height: 16),
              Text(l.topChits, style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(l.chitsComingSoon, style: t.bodyLarge?.copyWith(color: p.muted), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
