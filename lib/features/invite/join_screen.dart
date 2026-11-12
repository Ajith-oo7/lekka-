import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../l10n/app_localizations.dart';

/// Join with code: the borrower types (or arrives by link with) the lender's
/// invite code, joins the group and lands on the loan, where they accept the terms.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.initialCode});

  /// Filled in when the screen is opened from an invite link.
  final String? initialCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    if (_code.text.trim().isEmpty) {
      setState(() => _error = l.errorCodeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final loanId = await ref.read(repoProvider).joinWithCode(_code.text);
      refreshLoanData(ref);
      if (!mounted) return;
      // Home underneath, the loan on top, so Back works however we got here.
      final router = GoRouter.of(context);
      router.go(Routes.loans);
      router.push(Routes.loan(loanId));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.contains('INVITE_OWN')
            ? l.errorInviteOwn
            : e.message.contains('INVITE_INVALID')
                ? l.errorInviteInvalid
                : l.errorGeneric;
      });
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.joinWithCode),
        // When opened from a link there is nothing to go back to, so Close goes home.
        leading: IconButton(
          tooltip: l.cancel,
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.loans),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LekkaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.joinBody, style: t.bodyMedium?.copyWith(color: p.muted)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    autofocus: widget.initialCode == null,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 16,
                    style: t.titleLarge?.copyWith(letterSpacing: 2),
                    onSubmitted: (_) => _busy ? null : _join(),
                    decoration: InputDecoration(labelText: l.inviteCodeLabel, errorText: _error, counterText: ''),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(l.joinButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
