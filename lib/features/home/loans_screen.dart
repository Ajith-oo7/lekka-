import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/loan_math.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../loans/loan_card.dart';
import '../records/records_list.dart';
import 'summary_card.dart';

/// Home (Loans tab): user card with the Lent/Borrowed switch, summary card,
/// loans sorted by due date, and the 3 latest Records.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final side = ref.watch(loanSideProvider);
    final loansAsync = ref.watch(loansProvider);
    final entriesAsync = ref.watch(entriesProvider);

    final allLoans = loansAsync.valueOrNull ?? const <LoanView>[];
    final lentSide = side == LoanSide.lent;
    // Active loans on the chosen side, already sorted by due date.
    final sideLoans = allLoans.where((v) => v.isLender == lentSide && v.loan.isActive).toList();
    final sideIds = {for (final v in sideLoans) v.loan.id};
    final entries = entriesAsync.valueOrNull ?? const <LedgerEntry>[];

    final total = sideLoans.fold<int>(0, (sum, v) => sum + v.outstandingPaise);
    final monthly = sideLoans.fold<int>(
      0,
      (sum, v) => sum + monthlyInterestEstimate(v.outstandingPaise, v.loan.currentTerms),
    );
    final late = entries
        .where((e) => e.kind == EntryKind.lateInterest && sideIds.contains(e.loanId))
        .fold<int>(0, (sum, e) => sum + e.amountPaise);

    // Records preview: the 3 latest entries for loans on this side.
    final preview = entries.where((e) => sideIds.contains(e.loanId)).take(3).toList();
    final loansById = {for (final v in allLoans) v.loan.id: v};

    return RefreshIndicator(
      onRefresh: () async {
        refreshLoanData(ref);
        await ref.read(loansProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Extra bottom space so the New Loan button never covers the last row.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          const _UserCard(),
          const SizedBox(height: 10),
          SummaryCard(
            label: lentSide ? l.summaryLabelLent : l.summaryLabelBorrowed,
            activeCount: sideLoans.where((v) => v.status != LoanStatus.paid).length,
            totalPaise: total,
            monthlyInterestPaise: monthly,
            lateInterestPaise: late,
          ),
          const SizedBox(height: 10),
          SectionHeader(
            title: l.sectionLoans,
            action: lentSide
                ? TextButton.icon(
                    onPressed: () => context.push(Routes.groups),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(l.groupsTitle),
                  )
                : TextButton.icon(
                    onPressed: () => context.push(Routes.join),
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                    label: Text(l.joinWithCode),
                  ),
          ),
          const SizedBox(height: 6),
          AsyncBody(
            value: loansAsync,
            onRetry: () => refreshLoanData(ref),
            builder: (_) => sideLoans.isEmpty
                ? EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l.noLoansTitle,
                    body: lentSide ? l.noLoansLentBody : l.noLoansBorrowedBody,
                  )
                : Column(
                    children: [
                      for (final v in sideLoans) ...[
                        LoanCard(view: v, onTap: () => context.push(Routes.loan(v.loan.id))),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          SectionHeader(
            title: l.recordsPreviewTitle,
            action: TextButton(
              onPressed: () => context.go(Routes.records),
              child: Text(l.seeAll),
            ),
          ),
          const SizedBox(height: 6),
          if (preview.isEmpty)
            EmptyState(icon: Icons.receipt_long_outlined, title: l.noRecordsTitle)
          else
            RecordsList(entries: preview, loansById: loansById, showPersonName: true),
        ],
      ),
    );
  }
}

/// Greeting with the person's initials, and the Money Lent / Money Borrowed switch.
class _UserCard extends ConsumerWidget {
  const _UserCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(profileProvider).valueOrNull;

    // Profile name first; fall back to the name given at sign-up.
    final name = (profile?.name.isNotEmpty ?? false)
        ? profile!.name
        : (user?.userMetadata?['name'] as String? ?? '');

    return LekkaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.tint,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.tintBorder),
                ),
                child: Text(initials(name), style: t.titleSmall?.copyWith(color: p.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name.isEmpty ? l.greetingNoName : l.greeting(name),
                  style: t.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedSwitch<LoanSide>(
            options: [(LoanSide.lent, l.moneyLent), (LoanSide.borrowed, l.moneyBorrowed)],
            selected: ref.watch(loanSideProvider),
            onChanged: (s) => ref.read(loanSideProvider.notifier).set(s),
          ),
        ],
      ),
    );
  }
}
