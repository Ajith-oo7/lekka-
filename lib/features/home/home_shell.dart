import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import 'lekka_app_bar.dart';

/// The frame around the four tabs: app bar on top, bottom bar below.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final borrowedSide = ref.watch(loanSideProvider) == LoanSide.borrowed;
    return Scaffold(
      appBar: const LekkaAppBar(section: TopSection.loans),
      body: shell,
      // Green "New Loan" pill above the bottom bar, on the Loans tab only.
      floatingActionButton: shell.currentIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: LekkaColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add),
              label: Text(l.newLoan),
              onPressed: () => context.push(Routes.newLoan(borrowed: borrowedSide)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        // Tapping the current tab again scrolls it back to its start page.
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l.navLoans,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l.navRecords,
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: l.navReminders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: l.navSummary,
          ),
        ],
      ),
    );
  }
}
