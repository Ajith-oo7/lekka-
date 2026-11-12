import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inputs.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet to record a payment: amount, date, optional note.
/// Returns true when a payment was saved.
Future<bool?> showRecordPaymentSheet(BuildContext context, LoanView view) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecordPaymentSheet(view: view),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.view});

  final LoanView view;

  @override
  ConsumerState<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = today();
  String? _dateError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final loan = widget.view.loan;
    setState(() {
      _dateError = _date.isBefore(loan.startDate)
          ? l.errorPaymentBeforeStart
          : _date.isAfter(today())
              ? l.errorPaymentInFuture
              : null;
      _formError = null;
    });
    if (!_formKey.currentState!.validate() || _dateError != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).recordPayment(
            loanId: loan.id,
            amountPaise: parseHundredths(_amount.text)!,
            date: _date,
            note: _note.text,
          );
      refreshLoanData(ref);
      if (mounted) Navigator.pop(context, true);
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
    final lang = Localizations.localeOf(context).languageCode;
    final balance = widget.view.outstandingPaise;

    return Padding(
      // Keeps the fields above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.recordPayment, style: t.titleLarge),
                const SizedBox(height: 4),
                Text(l.balanceNow(formatRupees(balance)), style: t.bodySmall),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                  decoration: InputDecoration(labelText: l.amountLabel, prefixText: '₹ '),
                  validator: (v) {
                    final paise = parseHundredths(v ?? '');
                    if (paise == null || paise <= 0) return l.errorAmountRequired;
                    if (paise > balance) return l.errorMoreThanBalance(formatRupees(balance));
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: l.paymentDateLabel,
                  value: formatDate(_date, lang),
                  icon: Icons.event_outlined,
                  errorText: _dateError,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      // Guard for a loan dated in the future: the picker needs first <= last.
                      firstDate: widget.view.loan.startDate.isAfter(today()) ? today() : widget.view.loan.startDate,
                      lastDate: today(),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLength: 120,
                  decoration: InputDecoration(labelText: l.noteOptionalLabel),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(l.savePayment),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 10),
                  Text(_formError!, style: t.bodySmall?.copyWith(color: LekkaColors.overdueText)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
