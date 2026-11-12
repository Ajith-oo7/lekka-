import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../loans/loan_labels.dart';

/// A list of Records rows, newest first.
///
/// A payment that has been corrected is shown with a line through it, and the
/// correction appears as its own row: both stay visible. The lender can
/// correct a payment with a long press, which adds a reversal entry.
class RecordsList extends StatelessWidget {
  const RecordsList({
    super.key,
    required this.entries,
    required this.loansById,
    this.showPersonName = false,
  });

  final List<LedgerEntry> entries;
  final Map<String, LoanView> loansById;

  /// On the all-loans Records screen, show whose loan each row belongs to.
  final bool showPersonName;

  @override
  Widget build(BuildContext context) {
    final reversedIds = {for (final e in entries) if (e.reversesId != null) e.reversesId!};
    return LekkaCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const Divider(indent: 64),
            _RecordRow(
              entry: entries[i],
              loan: loansById[entries[i].loanId],
              reversed: reversedIds.contains(entries[i].id),
              showPersonName: showPersonName,
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordRow extends ConsumerWidget {
  const _RecordRow({
    required this.entry,
    required this.loan,
    required this.reversed,
    required this.showPersonName,
  });

  final LedgerEntry entry;
  final LoanView? loan;
  final bool reversed;
  final bool showPersonName;

  /// Plain-language detail line for the entry.
  String? _detail(AppLocalizations l) {
    if (entry.kind == EntryKind.termsChange) {
      // The database note is "Terms vN: …" in English; show the translated terms instead.
      final match = RegExp(r'Terms v(\d+)').firstMatch(entry.note ?? '');
      final version = match == null ? null : int.tryParse(match.group(1)!);
      final terms = version == null ? null : loan?.loan.termsVersion(version);
      if (terms != null) return l.termsVersionLine(terms.version, termsSummary(l, terms));
      return entry.note;
    }
    if (entry.kind == EntryKind.interestAccrual || entry.kind == EntryKind.lateInterest) {
      return interestNote(l, entry.note) ?? entry.note;
    }
    if (entry.kind == EntryKind.loanCreated) return null; // note is just "Loan created"
    if (entry.kind == EntryKind.reversal) return l.correctionNote;
    return entry.note;
  }

  /// Signed amount: what this row did to the balance.
  String? _amount() {
    if (entry.kind == EntryKind.termsChange) return null;
    // A correction undoes a payment, so it adds back to the balance.
    final sign = entry.kind == EntryKind.reversal ? 1 : entry.kind.sign;
    final text = formatRupees(entry.amountPaise);
    return sign < 0 ? '−$text' : '+$text';
  }

  Future<void> _correct(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.correctPaymentTitle),
        content: Text(l.correctPaymentBody(formatRupees(entry.amountPaise))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l.addCorrection)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repoProvider).reverseEntry(entry);
      refreshLoanData(ref);
      messenger.showSnackBar(SnackBar(content: Text(l.correctionAdded)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repoProvider).confirmPayment(entry.id);
      ref.invalidate(confirmationsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.paymentConfirmed)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final lang = Localizations.localeOf(context).languageCode;

    final canCorrect = entry.kind == EntryKind.payment &&
        !reversed &&
        (loan?.canWrite ?? false) &&
        (loan?.loan.isActive ?? false);

    // Shared loans: the borrower confirms payments the lender recorded.
    final shared = loan?.loan.isShared ?? false;
    final confirmed = ref.watch(confirmationsProvider).valueOrNull?.contains(entry.id) ?? false;
    final isLivePayment = entry.kind == EntryKind.payment && !reversed;
    final canConfirm = isLivePayment && shared && (loan?.iAmBorrower ?? false) && !confirmed;

    final strike = reversed ? TextDecoration.lineThrough : null;
    final amount = _amount();
    final detail = _detail(l);
    final amountColor = reversed
        ? p.muted
        : entry.kind == EntryKind.payment
            ? p.accent
            : entry.kind == EntryKind.lateInterest
                ? LekkaColors.dueSoonText
                : p.text;

    final dateLine = [
      formatDate(entry.entryDate, lang),
      if (showPersonName && loan != null && loan!.otherName.isNotEmpty) loan!.otherName,
    ].join(' · ');

    return InkWell(
      onLongPress: canCorrect ? () => _correct(context, ref) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
              child: Icon(entryIcon(entry.kind), size: 18, color: reversed ? p.muted : p.text),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entryLabel(l, entry.kind),
                    style: t.titleSmall?.copyWith(decoration: strike, color: reversed ? p.muted : null),
                  ),
                  const SizedBox(height: 2),
                  Text(dateLine, style: t.bodySmall),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(detail, style: t.bodySmall?.copyWith(decoration: strike)),
                  ],
                  if (reversed) ...[
                    const SizedBox(height: 2),
                    Text(l.correctedTag, style: t.labelSmall?.copyWith(color: LekkaColors.overdueText)),
                  ],
                  if (isLivePayment && shared && confirmed) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_outlined, size: 14, color: p.accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            loan!.iAmBorrower ? l.youConfirmed : l.confirmedByBorrower,
                            style: t.labelSmall?.copyWith(color: p.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (isLivePayment && shared && !confirmed && !loan!.iAmBorrower) ...[
                    const SizedBox(height: 2),
                    Text(l.notConfirmedYet, style: t.labelSmall),
                  ],
                  if (canConfirm)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text(l.confirmPayment),
                        onPressed: () => _confirm(context, ref),
                      ),
                    ),
                ],
              ),
            ),
            if (amount != null) ...[
              const SizedBox(width: 10),
              Text(
                amount,
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                  decoration: strike,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The daily job writes notes in one fixed English form, for example
/// "Simple interest 10.00% per month on ₹500" or
/// "Late interest 2.00% per month on ₹513.36" (see phase3_update.sql).
/// This turns them into the person's language. Returns null for any other text.
String? interestNote(AppLocalizations l, String? note) {
  if (note == null) return null;
  final regular = RegExp(r'^(Simple|Compound) interest ([\d.]+)% per (day|week|month|year) on (₹[\d,.]+)$').firstMatch(note);
  if (regular != null) {
    final bps = parseHundredths(regular.group(2)!);
    if (bps == null) return null;
    final type = regular.group(1) == 'Simple' ? InterestType.simple : InterestType.compound;
    return l.noteInterest(
      interestTypeLabel(l, type),
      rateText(l, bps, RatePeriod.fromDb(regular.group(3)!)),
      regular.group(4)!,
    );
  }
  final late = RegExp(r'^Late interest ([\d.]+)% per (day|week|month|year) on (₹[\d,.]+)$').firstMatch(note);
  if (late != null) {
    final bps = parseHundredths(late.group(1)!);
    if (bps == null) return null;
    return l.noteLateInterest(rateText(l, bps, RatePeriod.fromDb(late.group(2)!)), late.group(3)!);
  }
  return null;
}
