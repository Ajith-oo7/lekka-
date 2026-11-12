import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import 'loan_labels.dart';

/// Shown to a borrower who has joined a shared loan and not yet accepted:
/// the terms in plain words and an Accept button. The borrower cannot change
/// terms, only accept them.
class AcceptTermsCard extends ConsumerStatefulWidget {
  const AcceptTermsCard({super.key, required this.view, required this.terms});

  final LoanView view;
  final LoanTerms terms;

  @override
  ConsumerState<AcceptTermsCard> createState() => _AcceptTermsCardState();
}

class _AcceptTermsCardState extends ConsumerState<AcceptTermsCard> {
  bool _busy = false;

  Future<void> _accept() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).acceptTerms(widget.terms.id);
      refreshLoanData(ref);
      messenger.showSnackBar(SnackBar(content: Text(l.termsAcceptedDone)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LekkaColors.dueSoonBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LekkaColors.dueSoonBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed dark text: this card keeps its light amber background in dark mode.
          Text(l.acceptTermsTitle, style: t.titleMedium?.copyWith(color: const Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(
            l.acceptTermsBody(widget.view.otherName),
            style: t.bodyMedium?.copyWith(color: const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(
            termsSummary(l, widget.terms),
            style: t.titleSmall?.copyWith(color: LekkaColors.dueSoonText),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _accept,
            child: Text(l.acceptTermsButton),
          ),
        ],
      ),
    );
  }
}

/// "Invite {name}": makes an invite code and shows it with copy buttons.
class InviteButton extends ConsumerStatefulWidget {
  const InviteButton({super.key, required this.view});

  final LoanView view;

  @override
  ConsumerState<InviteButton> createState() => _InviteButtonState();
}

class _InviteButtonState extends ConsumerState<InviteButton> {
  bool _busy = false;

  Future<void> _invite() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final code = await ref.read(repoProvider).createInvite(widget.view.loan.id);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _InviteDialog(code: code));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OutlinedButton.icon(
      icon: const Icon(Icons.person_add_alt),
      label: Text(l.inviteBorrower(widget.view.otherName)),
      onPressed: _busy ? null : _invite,
    );
  }
}

/// Writes the code as XXXXX-XXXXX so it is easier to read out and type.
String formatInviteCode(String code) =>
    code.length == 10 ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final shown = formatInviteCode(code);
    // The link opens the app on the join screen once app links are set up (see README).
    final link = 'lekka://join/$code';

    Future<void> copy(String text) async {
      final messenger = ScaffoldMessenger.of(context);
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(SnackBar(content: Text(l.copied)));
    }

    return AlertDialog(
      title: Text(l.inviteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.inviteBody, style: t.bodyMedium),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.chip, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(
              shown,
              textAlign: TextAlign.center,
              style: t.headlineSmall?.copyWith(letterSpacing: 2),
            ),
          ),
          const SizedBox(height: 8),
          Text(l.inviteExpiry, style: t.bodySmall),
        ],
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(onPressed: () => copy(shown), child: Text(l.copyCode)),
        TextButton(onPressed: () => copy(l.inviteMessage(shown, link)), child: Text(l.copyInviteMessage)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.done)),
      ],
    );
  }
}

/// "Close loan", with a confirmation. A closed loan stops getting interest.
class CloseLoanButton extends ConsumerWidget {
  const CloseLoanButton({super.key, required this.view});

  final LoanView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: LekkaColors.overdueText),
      icon: const Icon(Icons.lock_outline, size: 18),
      label: Text(l.closeLoan),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(l.closeLoanTitle),
            content: Text(view.outstandingPaise > 0 ? l.closeLoanBodyUnpaid : l.closeLoanBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l.closeLoan)),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(repoProvider).closeLoan(view.loan.id);
          refreshLoanData(ref);
          messenger.showSnackBar(SnackBar(content: Text(l.loanClosedDone)));
        } catch (_) {
          messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
        }
      },
    );
  }
}

/// "Send ping": the lender of a shared loan nudges the borrower with a push
/// notification. The server allows at most 3 a day for each loan.
class PingButton extends ConsumerStatefulWidget {
  const PingButton({super.key, required this.view});

  final LoanView view;

  @override
  ConsumerState<PingButton> createState() => _PingButtonState();
}

class _PingButtonState extends ConsumerState<PingButton> {
  bool _busy = false;

  Future<void> _ping() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).sendPing(widget.view.loan.id);
      messenger.showSnackBar(SnackBar(content: Text(l.pingSent(widget.view.otherName))));
    } on FunctionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.status == 429 ? l.errorPingLimit : l.errorGeneric)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return OutlinedButton.icon(
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(l.sendPing),
      onPressed: _busy ? null : _ping,
    );
  }
}
