import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/loan_math.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Summary: totals lent and borrowed, interest earned, late interest added,
/// and the number of active loans by status.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final p = LekkaPalette.of(context);
    final loansAsync = ref.watch(loansProvider);
    final entries = ref.watch(entriesProvider).valueOrNull ?? const <LedgerEntry>[];

    return RefreshIndicator(
      onRefresh: () async {
        refreshLoanData(ref);
        await ref.read(loansProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: l.navSummary),
          const SizedBox(height: 6),
          AsyncBody(
            value: loansAsync,
            onRetry: () => refreshLoanData(ref),
            builder: (loans) {
              final active = loans.where((v) => v.loan.isActive).toList();
              final lentIds = {for (final v in loans) if (v.isLender) v.loan.id};

              int sumOutstanding(bool lent) => active
                  .where((v) => v.isLender == lent)
                  .fold(0, (sum, v) => sum + v.outstandingPaise);
              int sumEntries(Set<EntryKind> kinds) => entries
                  .where((e) => kinds.contains(e.kind) && lentIds.contains(e.loanId))
                  .fold(0, (sum, e) => sum + e.amountPaise);
              int count(LoanStatus s) => active.where((v) => v.status == s).length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LekkaCard(
                    child: Column(
                      children: [
                        _AmountRow(label: l.summaryTotalLent, paise: sumOutstanding(true)),
                        _AmountRow(label: l.summaryTotalBorrowed, paise: sumOutstanding(false)),
                        _AmountRow(
                          label: l.summaryInterestEarned,
                          paise: sumEntries({EntryKind.interestAccrual, EntryKind.lateInterest}),
                          color: p.accent,
                        ),
                        _AmountRow(
                          label: l.lateInterestAdded,
                          paise: sumEntries({EntryKind.lateInterest}),
                          color: LekkaColors.dueSoonText,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SectionHeader(title: l.summaryLoansByStatus),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _StatusTile(
                          label: l.statusOnTrack,
                          count: count(LoanStatus.onTrack),
                          text: p.accent,
                          bg: p.tint,
                          border: p.tintBorder,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatusTile(
                          label: l.statusDueSoon,
                          count: count(LoanStatus.dueSoon),
                          text: LekkaColors.dueSoonText,
                          bg: LekkaColors.dueSoonBg,
                          border: LekkaColors.dueSoonBorder,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatusTile(
                          label: l.statusOverdue,
                          count: count(LoanStatus.overdue),
                          text: LekkaColors.overdueText,
                          bg: LekkaColors.overdueBg,
                          border: LekkaColors.overdueBorder,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.paise, this.color});

  final String label;
  final int paise;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          const SizedBox(width: 12),
          Text(formatRupees(paise), style: t.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// A small coloured tile: count on top, status name below.
class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.count,
    required this.text,
    required this.bg,
    required this.border,
  });

  final String label;
  final int count;
  final Color text;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count', style: t.headlineSmall?.copyWith(color: text)),
          const SizedBox(height: 2),
          Text(label, style: t.labelMedium?.copyWith(color: text)),
        ],
      ),
    );
  }
}
