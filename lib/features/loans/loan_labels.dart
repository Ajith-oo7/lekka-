import 'package:flutter/material.dart';

import '../../core/loan_math.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Translated words for loan data, kept in one place.

String statusLabel(AppLocalizations l, LoanStatus s) => switch (s) {
      LoanStatus.onTrack => l.statusOnTrack,
      LoanStatus.dueSoon => l.statusDueSoon,
      LoanStatus.overdue => l.statusOverdue,
      LoanStatus.paid => l.statusPaid,
    };

/// (text, background, border) colours for a status pill.
(Color, Color, Color) statusColors(BuildContext context, LoanStatus s) {
  final p = LekkaPalette.of(context);
  return switch (s) {
    LoanStatus.onTrack => (p.accent, p.tint, p.tintBorder),
    LoanStatus.paid => (p.muted, p.chip, p.line),
    LoanStatus.dueSoon => (LekkaColors.dueSoonText, LekkaColors.dueSoonBg, LekkaColors.dueSoonBorder),
    LoanStatus.overdue => (LekkaColors.overdueText, LekkaColors.overdueBg, LekkaColors.overdueBorder),
  };
}

/// "10% per month" (word order follows the language).
String rateText(AppLocalizations l, int bps, RatePeriod period) {
  final rate = formatPercent(bps);
  return switch (period) {
    RatePeriod.day => l.ratePerDay(rate),
    RatePeriod.week => l.ratePerWeek(rate),
    RatePeriod.month => l.ratePerMonth(rate),
    RatePeriod.year => l.ratePerYear(rate),
  };
}

String periodLabel(AppLocalizations l, RatePeriod p) => switch (p) {
      RatePeriod.day => l.periodDay,
      RatePeriod.week => l.periodWeek,
      RatePeriod.month => l.periodMonth,
      RatePeriod.year => l.periodYear,
    };

String interestTypeLabel(AppLocalizations l, InterestType t) =>
    t == InterestType.simple ? l.interestSimple : l.interestCompound;

String lateText(AppLocalizations l, LoanTerms t) => t.lateRateBps == 0
    ? l.noLateInterest
    : l.lateTerms(rateText(l, t.lateRateBps, t.ratePeriod), t.graceDays);

/// One line describing a terms version: "10% per month, Simple. Late: …".
String termsSummary(AppLocalizations l, LoanTerms t) => l.termsLine(
      rateText(l, t.rateBps, t.ratePeriod),
      interestTypeLabel(l, t.interestType),
      lateText(l, t),
    );

String entryLabel(AppLocalizations l, EntryKind k) => switch (k) {
      EntryKind.loanCreated => l.entryLoanGiven,
      EntryKind.payment => l.entryPaymentReceived,
      EntryKind.interestAccrual => l.entryInterestAdded,
      EntryKind.lateInterest => l.entryLateInterestAdded,
      EntryKind.termsChange => l.entryTermsUpdated,
      EntryKind.reversal => l.entryCorrection,
    };

IconData entryIcon(EntryKind k) => switch (k) {
      EntryKind.loanCreated => Icons.north_east,
      EntryKind.payment => Icons.south_west,
      EntryKind.interestAccrual => Icons.percent,
      EntryKind.lateInterest => Icons.schedule,
      EntryKind.termsChange => Icons.edit_note,
      EntryKind.reversal => Icons.undo,
    };

/// Small rounded pill with the loan status.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final LoanStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (text, bg, border) = statusColors(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        statusLabel(l, status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: text, fontWeight: FontWeight.w600),
      ),
    );
  }
}
