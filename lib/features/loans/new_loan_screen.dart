import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/inputs.dart';
import '../../core/money.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../groups/new_group_dialog.dart';
import 'borrower_picker.dart';
import 'terms_fields.dart';

/// New loan: group, borrower, amount, interest % and period, simple or
/// compound, late interest % and grace days, start date, next due date.
/// Saving creates the loan and terms version 1 together.
class NewLoanScreen extends ConsumerStatefulWidget {
  const NewLoanScreen({super.key, this.groupId, this.iAmBorrower = false});

  /// Pre-selected group when opened from a group page.
  final String? groupId;

  /// Start on "I took this loan" (solo borrower mode).
  final bool iAmBorrower;

  @override
  ConsumerState<NewLoanScreen> createState() => _NewLoanScreenState();
}

class _NewLoanScreenState extends ConsumerState<NewLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _lateRate = TextEditingController(text: '0');
  final _grace = TextEditingController(text: '0');

  String? _groupId;
  Contact? _borrower;
  late bool _iAmBorrower = widget.iAmBorrower;
  RatePeriod _period = RatePeriod.month;
  InterestType _type = InterestType.simple;
  late DateTime _start;
  late DateTime _due;

  String? _groupError;
  String? _borrowerError;
  String? _dueError;
  String? _formError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
    _start = today();
    _due = _start.add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _lateRate.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _chooseGroup(List<LoanGroup> groups) async {
    final l = AppLocalizations.of(context);
    const newGroup = '__new__';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(l.chooseGroup, style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.create_new_folder_outlined, color: LekkaPalette.of(c).accent),
              title: Text(l.newGroup),
              onTap: () => Navigator.pop(c, newGroup),
            ),
            const Divider(),
            for (final g in groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(g.name),
                trailing: g.id == _groupId ? Icon(Icons.check_circle, color: LekkaPalette.of(c).accent) : null,
                onTap: () => Navigator.pop(c, g.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == newGroup) {
      final group = await showNewGroupDialog(context);
      if (group != null) setState(() => _groupId = group.id);
    } else {
      setState(() => _groupId = picked);
    }
    setState(() => _groupError = null);
  }

  Future<void> _chooseBorrower() async {
    final contact = await pickBorrower(context, lender: _iAmBorrower);
    if (contact != null && mounted) {
      setState(() {
        _borrower = contact;
        _borrowerError = null;
      });
    }
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _groupError = _groupId == null ? l.errorChooseGroup : null;
      _borrowerError = _borrower == null ? (_iAmBorrower ? l.errorChooseLender : l.errorChooseBorrower) : null;
      _dueError = _due.isBefore(_start) ? l.errorDueBeforeStart : null;
      _formError = null;
    });
    final fieldsOk = _formKey.currentState!.validate();
    if (!fieldsOk || _groupError != null || _borrowerError != null || _dueError != null) return;

    setState(() => _busy = true);
    try {
      final id = await ref.read(repoProvider).createLoan(
            groupId: _groupId!,
            contactId: _borrower!.id,
            principalPaise: parseHundredths(_amount.text)!,
            startDate: _start,
            nextDueDate: _due,
            rateBps: parseHundredths(_rate.text)!,
            ratePeriod: _period,
            interestType: _type,
            lateRateBps: parseHundredths(_lateRate.text)!,
            graceDays: int.parse(_grace.text),
            iAmBorrower: _iAmBorrower,
          );
      refreshLoanData(ref);
      if (mounted) context.pushReplacement(Routes.loan(id));
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
    // Only groups the person owns: a loan can be added only to your own group.
    final me = ref.watch(currentUserProvider)?.id;
    final groups = (ref.watch(groupsProvider).valueOrNull ?? const <LoanGroup>[])
        .where((g) => g.ownerId == me)
        .toList();

    String? groupName;
    for (final g in groups) {
      if (g.id == _groupId) groupName = g.name;
    }

    String? amountValidator(String? v) {
      final paise = parseHundredths(v ?? '');
      return (paise == null || paise <= 0) ? l.errorAmountRequired : null;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.newLoan)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LekkaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedSwitch<bool>(
                      options: [(false, l.iGaveLoan), (true, l.iTookLoan)],
                      selected: _iAmBorrower,
                      onChanged: (v) => setState(() => _iAmBorrower = v),
                    ),
                    if (_iAmBorrower) ...[
                      const SizedBox(height: 6),
                      Text(l.iTookLoanHelp, style: t.bodySmall),
                    ],
                    const SizedBox(height: 14),
                    PickerField(
                      label: l.groupLabel,
                      value: groupName,
                      placeholder: l.chooseGroup,
                      icon: Icons.folder_outlined,
                      errorText: _groupError,
                      onTap: () => _chooseGroup(groups),
                    ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: _iAmBorrower ? l.lenderLabel : l.borrowerLabel,
                      value: _borrower?.name,
                      placeholder: _iAmBorrower ? l.chooseLender : l.chooseBorrower,
                      icon: Icons.person_outline,
                      errorText: _borrowerError,
                      onTap: _chooseBorrower,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [DecimalInputFormatter()],
                      decoration: InputDecoration(labelText: l.amountLabel, prefixText: '₹ '),
                      validator: amountValidator,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionHeader(title: l.interestSection),
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
              SectionHeader(title: l.datesSection),
              const SizedBox(height: 6),
              LekkaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PickerField(
                      label: l.startDateLabel,
                      value: formatDate(_start, lang),
                      icon: Icons.event_outlined,
                      onTap: () async {
                        final d = await _pickDate(_start);
                        if (d != null) setState(() => _start = d);
                      },
                    ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: l.nextDueDateLabel,
                      value: formatDate(_due, lang),
                      icon: Icons.event_available_outlined,
                      errorText: _dueError,
                      onTap: () async {
                        final d = await _pickDate(_due);
                        if (d != null) setState(() => _due = d);
                      },
                    ),
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
                    : Text(l.saveLoan),
              ),
              if (_formError != null) ...[
                const SizedBox(height: 10),
                Text(_formError!, style: t.bodySmall?.copyWith(color: LekkaColors.overdueText)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
