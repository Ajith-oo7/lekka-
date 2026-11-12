import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import 'loan_labels.dart';
import 'terms_fields.dart';

/// Change terms: saves a NEW terms version. The old version is never edited,
/// and Records gets a "Terms updated" entry. New terms count from today;
/// days already passed keep the old terms.
class ChangeTermsScreen extends ConsumerWidget {
  const ChangeTermsScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final viewAsync = ref.watch(loanViewProvider(loanId));
    return Scaffold(
      appBar: AppBar(title: Text(l.changeTerms)),
      body: AsyncBody(
        value: viewAsync,
        onRetry: () => refreshLoanData(ref),
        builder: (view) {
          final terms = view?.loan.currentTerms;
          if (view == null || terms == null || !view.canWrite) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: EmptyState(icon: Icons.search_off, title: l.loanNotFound),
            );
          }
          return _ChangeTermsForm(loan: view.loan, current: terms);
        },
      ),
    );
  }
}

class _ChangeTermsForm extends ConsumerStatefulWidget {
  const _ChangeTermsForm({required this.loan, required this.current});

  final Loan loan;
  final LoanTerms current;

  @override
  ConsumerState<_ChangeTermsForm> createState() => _ChangeTermsFormState();
}

class _ChangeTermsFormState extends ConsumerState<_ChangeTermsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _rate = TextEditingController(text: _bpsToInput(widget.current.rateBps));
  late final _lateRate = TextEditingController(text: _bpsToInput(widget.current.lateRateBps));
  late final _grace = TextEditingController(text: '${widget.current.graceDays}');
  late RatePeriod _period = widget.current.ratePeriod;
  late InterestType _type = widget.current.interestType;
  String? _formError;
  bool _busy = false;

  /// 1050 → "10.5", 1000 → "10" (what the person would type).
  static String _bpsToInput(int bps) => formatPercent(bps).replaceAll('%', '');

  @override
  void dispose() {
    _rate.dispose();
    _lateRate.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;

    final rateBps = parseHundredths(_rate.text)!;
    final lateBps = parseHundredths(_lateRate.text)!;
    final grace = int.parse(_grace.text);
    final c = widget.current;
    if (rateBps == c.rateBps &&
        lateBps == c.lateRateBps &&
        grace == c.graceDays &&
        _period == c.ratePeriod &&
        _type == c.interestType) {
      setState(() => _formError = l.errorTermsUnchanged);
      return;
    }

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repoProvider).changeTerms(
            loan: widget.loan,
            rateBps: rateBps,
            ratePeriod: _period,
            interestType: _type,
            lateRateBps: lateBps,
            graceDays: grace,
          );
      refreshLoanData(ref);
      messenger.showSnackBar(SnackBar(content: Text(l.termsSaved)));
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => _formError = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final c = widget.current;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LekkaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.currentTermsVersion(c.version), style: t.labelMedium?.copyWith(color: p.muted)),
                  const SizedBox(height: 4),
                  Text(termsSummary(l, c), style: t.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SectionHeader(title: l.newTermsVersion(c.version + 1)),
            const SizedBox(height: 6),
            TermsFields(
              rate: _rate,
              lateRate: _lateRate,
              grace: _grace,
              period: _period,
              type: _type,
              onPeriod: (v) => setState(() => _period = v),
              onType: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.tintBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l.changeTermsInfo, style: t.bodySmall?.copyWith(color: p.text))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(l.saveNewTerms),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 10),
              Text(_formError!, style: t.bodySmall?.copyWith(color: LekkaColors.overdueText)),
            ],
          ],
        ),
      ),
    );
  }
}
