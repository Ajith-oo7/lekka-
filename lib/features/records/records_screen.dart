import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../l10n/app_localizations.dart';
import 'records_list.dart';

/// Records (all loans): every entry across all loans, newest first.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entries = ref.watch(entriesProvider);
    final loans = ref.watch(loansProvider);

    return RefreshIndicator(
      onRefresh: () async {
        refreshLoanData(ref);
        await ref.read(entriesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SectionHeader(title: l.navRecords),
          const SizedBox(height: 6),
          AsyncBody(
            value: entries,
            onRetry: () => refreshLoanData(ref),
            builder: (list) => list.isEmpty
                ? EmptyState(icon: Icons.receipt_long_outlined, title: l.noRecordsTitle, body: l.noRecordsBody)
                : RecordsList(
                    entries: list,
                    loansById: {for (final v in loans.valueOrNull ?? const <LoanView>[]) v.loan.id: v},
                    showPersonName: true,
                  ),
          ),
          const SizedBox(height: 8),
          if ((entries.valueOrNull ?? const []).isNotEmpty)
            Text(l.longPressHint, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
