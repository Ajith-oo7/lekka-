import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../records/records_list.dart';
import 'loan_actions.dart';
import 'loan_labels.dart';
import 'record_payment_sheet.dart';

/// Loan detail: outstanding balance, the current terms, "Record payment",
/// and this loan's Records below.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final viewAsync = ref.watch(loanViewProvider(loanId));
    final entriesAsync = ref.watch(entriesProvider);
    final name = viewAsync.valueOrNull?.otherName;

    return Scaffold(
      appBar: AppBar(title: Text(name == null || name.isEmpty ? l.loanTitle : name)),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshLoanData(ref);
          await ref.read(loansProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            AsyncBody(
              value: viewAsync,
              onRetry: () => refreshLoanData(ref),
              builder: (view) {
                if (view == null) {
                  // Not found, or this account is not allowed to see it.
                  return EmptyState(icon: Icons.search_off, title: l.loanNotFound);
                }
                final entries = (entriesAsync.valueOrNull ?? const <LedgerEntry>[])
                    .where((e) => e.loanId == loanId)
                    .toList();
                return _LoanBody(view: view, entries: entries);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanBody extends StatelessWidget {
  const _LoanBody({required this.view, required this.entries});

  final LoanView view;
  final List<LedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final loan = view.loan;
    final terms = loan.currentTerms;
    final canRecord = view.canWrite && loan.isActive && view.outstandingPaise > 0;
    // A loan the lender tracks alone can be shared by inviting the borrower.
    final canInvite = view.canWrite && !view.iAmBorrower && loan.borrowerUserId == null && loan.isActive;
    final mustAccept = view.iAmBorrower && loan.isShared && !loan.termsAccepted && terms != null;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: p.muted))),
              const SizedBox(width: 12),
              Flexible(child: Text(value, style: t.titleSmall, textAlign: TextAlign.end)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!loan.isActive) ...[
          InfoBanner(icon: Icons.lock_outline, text: l.loanClosedNote),
          const SizedBox(height: 10),
        ],
        if (mustAccept) ...[
          AcceptTermsCard(view: view, terms: terms!),
          const SizedBox(height: 10),
        ],
        // Balance card, in the summary card style.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LekkaColors.summaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.isLender ? l.owesYou : l.youOwe,
                      style: t.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
                    ),
                  ),
                  StatusPill(status: view.status),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRupees(view.outstandingPaise),
                  style: t.displaySmall?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.outstandingBalance,
                style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        LekkaCard(
          child: Column(
            children: [
              row(l.amountGiven, formatRupees(loan.principalPaise)),
              if (loan.groupName.isNotEmpty) row(l.groupLabel, loan.groupName),
              row(l.startDateLabel, formatDate(loan.startDate, lang)),
              if (loan.nextDueDate != null) row(l.nextDueDateLabel, formatDate(loan.nextDueDate!, lang)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionHeader(title: terms == null ? l.currentTerms : l.currentTermsVersion(terms.version)),
        const SizedBox(height: 6),
        LekkaCard(
          child: terms == null
              ? Text(l.noTerms, style: t.bodyMedium)
              : Column(
                  children: [
                    row(l.interestRateLabel, rateText(l, terms.rateBps, terms.ratePeriod)),
                    row(l.interestTypeLabel, interestTypeLabel(l, terms.interestType)),
                    row(
                      l.lateRateLabel,
                      terms.lateRateBps == 0 ? l.noLateInterest : rateText(l, terms.lateRateBps, terms.ratePeriod),
                    ),
                    row(l.graceDaysLabel, l.daysCount(terms.graceDays)),
                  ],
                ),
        ),
        if (loan.isShared && !view.iAmBorrower && terms != null) ...[
          const SizedBox(height: 8),
          Text(
            loan.termsAccepted ? l.termsAcceptedBy(view.otherName) : l.termsWaiting(view.otherName),
            style: t.bodySmall?.copyWith(color: loan.termsAccepted ? p.accent : LekkaColors.dueSoonText),
          ),
        ],
        if (view.canWrite && loan.isActive && terms != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.changeTerms),
              onPressed: () => context.push(Routes.changeTerms(loan.id)),
            ),
          ),
        ],
        if (canRecord) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: const Icon(Icons.payments_outlined),
            label: Text(l.recordPayment),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final saved = await showRecordPaymentSheet(context, view);
              if (saved == true) messenger.showSnackBar(SnackBar(content: Text(l.paymentSaved)));
            },
          ),
        ],
        if (loan.isShared && !view.iAmBorrower && view.canWrite && loan.isActive) ...[
          const SizedBox(height: 10),
          PingButton(view: view),
        ],
        if (canInvite) ...[
          const SizedBox(height: 10),
          InviteButton(view: view),
        ],
        if (view.canWrite && loan.isActive) ...[
          const SizedBox(height: 4),
          CloseLoanButton(view: view),
        ],
        const SizedBox(height: 14),
        SectionHeader(title: l.navRecords),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          EmptyState(icon: Icons.receipt_long_outlined, title: l.noRecordsTitle)
        else ...[
          RecordsList(entries: entries, loansById: {loan.id: view}),
          if (view.canWrite && loan.isActive) ...[
            const SizedBox(height: 8),
            Text(l.longPressHint, style: t.bodySmall, textAlign: TextAlign.center),
          ],
        ],
      ],
    );
  }
}
