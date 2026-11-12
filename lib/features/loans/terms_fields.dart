import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/inputs.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import 'loan_labels.dart';

/// The interest terms inputs, shared by New loan and Change terms:
/// interest %, period, simple or compound, late interest % and grace days.
class TermsFields extends StatelessWidget {
  const TermsFields({
    super.key,
    required this.rate,
    required this.lateRate,
    required this.grace,
    required this.period,
    required this.type,
    required this.onPeriod,
    required this.onType,
  });

  final TextEditingController rate;
  final TextEditingController lateRate;
  final TextEditingController grace;
  final RatePeriod period;
  final InterestType type;
  final ValueChanged<RatePeriod> onPeriod;
  final ValueChanged<InterestType> onType;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);

    String? rateValidator(String? v) => parseHundredths(v ?? '') == null ? l.errorRateInvalid : null;

    return LekkaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [DecimalInputFormatter()],
            decoration: InputDecoration(labelText: l.interestRateLabel, suffixText: '%'),
            validator: rateValidator,
          ),
          const SizedBox(height: 12),
          Text(l.interestPeriodLabel, style: t.labelMedium?.copyWith(color: p.muted)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in RatePeriod.values)
                ChoiceChip(
                  label: Text(
                    periodLabel(l, option),
                    style: option == period ? const TextStyle(color: Colors.white) : null,
                  ),
                  selected: option == period,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => onPeriod(option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l.interestTypeLabel, style: t.labelMedium?.copyWith(color: p.muted)),
          const SizedBox(height: 6),
          SegmentedSwitch<InterestType>(
            options: [
              (InterestType.simple, l.interestSimple),
              (InterestType.compound, l.interestCompound),
            ],
            selected: type,
            onChanged: onType,
          ),
          const SizedBox(height: 4),
          Text(type == InterestType.simple ? l.interestSimpleHelp : l.interestCompoundHelp, style: t.bodySmall),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: lateRate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                  decoration: InputDecoration(labelText: l.lateRateLabel, suffixText: '%'),
                  validator: rateValidator,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: grace,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(labelText: l.graceDaysLabel),
                  validator: (v) => int.tryParse(v ?? '') == null ? l.errorGraceDays : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l.lateRateHelp, style: t.bodySmall),
        ],
      ),
    );
  }
}
