import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Language names, each written in its own script (English, తెలుగు, हिन्दी).
List<(String, String)> languageOptions(AppLocalizations l) => [
      ('en', l.langEnglish),
      ('te', l.langTelugu),
      ('hi', l.langHindi),
    ];

/// Three round chips for the sign-up / sign-in screen.
class LanguageChips extends StatelessWidget {
  const LanguageChips({super.key, required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (code, label) in languageOptions(l))
          ChoiceChip(
            label: Text(label, style: code == selected ? const TextStyle(color: Colors.white) : null),
            selected: code == selected,
            showCheckmark: false,
            materialTapTargetSize: MaterialTapTargetSize.padded, // 48 px tap area
            onSelected: (_) => onSelected(code),
          ),
      ],
    );
  }
}
