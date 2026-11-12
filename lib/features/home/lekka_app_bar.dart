import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../l10n/app_localizations.dart';

enum TopSection { loans, chits }

/// App bar: logo tile, "Lekka" with the tagline, the Loans/Chits pill and Settings.
class LekkaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LekkaAppBar({super.key, required this.section});

  final TopSection section;

  // Room for the name and tagline even with Telugu/Hindi line heights.
  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);

    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: 16,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const LogoTile(),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.appName, style: t.titleLarge, maxLines: 1),
                Text(
                  l.tagline,
                  style: t.labelSmall?.copyWith(color: p.muted),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Center(
          child: SegmentedSwitch<TopSection>(
            compact: true,
            options: [(TopSection.loans, l.topLoans), (TopSection.chits, l.topChits)],
            selected: section,
            onChanged: (s) => context.go(s == TopSection.loans ? Routes.loans : Routes.chits),
          ),
        ),
        IconButton(
          tooltip: l.settingsTitle,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push(Routes.settings),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
