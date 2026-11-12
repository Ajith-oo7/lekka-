import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/loan_math.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../l10n/app_localizations.dart';
import 'loan_labels.dart';

/// Loan row: avatar with initials, name and status pill, muted subtitle;
/// on the right "owes you"/"you owe", the amount and the rate.
/// Overdue rows get a rose border and a rose amount.
class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.view, required this.onTap});

  final LoanView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final loan = view.loan;
    final overdue = view.status == LoanStatus.overdue;
    final terms = loan.currentTerms;

    final subtitle = [
      if (loan.groupName.isNotEmpty) loan.groupName,
      if (loan.nextDueDate != null) l.dueOn(formatDate(loan.nextDueDate!, lang)),
    ].join(' · ');

    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: overdue ? LekkaColors.overdueBorder : p.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: overdue ? LekkaColors.overdueAvatarBg : p.tint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials(view.otherName),
                  style: t.titleSmall?.copyWith(color: overdue ? LekkaColors.overdueAvatarText : p.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(view.otherName, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        StatusPill(status: view.status),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: t.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(view.isLender ? l.owesYou : l.youOwe, style: t.labelSmall),
                  Text(
                    formatRupees(view.outstandingPaise),
                    style: t.titleMedium?.copyWith(
                      fontSize: 17,
                      color: overdue ? LekkaColors.overdueText : null,
                    ),
                  ),
                  if (terms != null)
                    Text(rateText(l, terms.rateBps, terms.ratePeriod), style: t.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
