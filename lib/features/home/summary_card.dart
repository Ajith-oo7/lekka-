import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';

/// The green gradient card: label + "N active" pill, big total, then
/// monthly interest and late interest added (in amber).
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.activeCount,
    required this.totalPaise,
    required this.monthlyInterestPaise,
    required this.lateInterestPaise,
  });

  final String label;
  final int activeCount;
  final int totalPaise;
  final int monthlyInterestPaise;
  final int lateInterestPaise;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.72);

    Widget column(String title, int paise, Color amountColor) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.labelSmall?.copyWith(color: soft)),
              const SizedBox(height: 2),
              Text(formatRupees(paise), style: t.titleMedium?.copyWith(color: amountColor)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LekkaColors.summaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: t.labelMedium?.copyWith(color: soft))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(l.activeCount(activeCount), style: t.labelSmall?.copyWith(color: white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatRupees(totalPaise), style: t.displaySmall?.copyWith(color: white)),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(l.monthlyInterest, monthlyInterestPaise, white),
              const SizedBox(width: 12),
              column(l.lateInterestAdded, lateInterestPaise, LekkaColors.highlightOnDark),
            ],
          ),
        ],
      ),
    );
  }
}
