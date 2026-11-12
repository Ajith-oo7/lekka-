import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../loans/loan_card.dart';

/// One group: its loans, and a button to add a loan to it.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final groups = ref.watch(groupsProvider).valueOrNull ?? const <LoanGroup>[];
    final loansAsync = ref.watch(loansProvider);
    final me = ref.watch(currentUserProvider)?.id;

    LoanGroup? group;
    for (final g in groups) {
      if (g.id == groupId) group = g;
    }
    final isOwner = group != null && group.ownerId == me;

    return Scaffold(
      appBar: AppBar(title: Text(group?.name ?? l.groupsTitle)),
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              backgroundColor: LekkaColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add),
              label: Text(l.newLoan),
              onPressed: () => context.push(Routes.newLoan(groupId: groupId)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          refreshLoanData(ref);
          await ref.read(loansProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            AsyncBody(
              value: loansAsync,
              onRetry: () => refreshLoanData(ref),
              builder: (all) {
                final loans = all.where((v) => v.loan.groupId == groupId).toList();
                if (loans.isEmpty) {
                  return EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l.noLoansTitle,
                    body: l.noLoansInGroupBody,
                  );
                }
                return Column(
                  children: [
                    for (final v in loans) ...[
                      LoanCard(view: v, onTap: () => context.push(Routes.loan(v.loan.id))),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
