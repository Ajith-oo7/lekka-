import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Bottom sheet: pick an existing contact or add a new person (name, optional phone).
/// Returns the chosen contact, or null if dismissed.
Future<Contact?> pickBorrower(BuildContext context, {bool lender = false}) {
  return showModalBottomSheet<Contact>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _BorrowerSheet(lender: lender),
  );
}

class _BorrowerSheet extends ConsumerWidget {
  const _BorrowerSheet({required this.lender});

  /// True when picking the lender of a loan the person took.
  final bool lender;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final contactsAsync = ref.watch(contactsProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(lender ? l.chooseLender : l.chooseBorrower, style: t.titleLarge),
            const SizedBox(height: 10),
            ListTile(
              leading: CircleAvatar(backgroundColor: p.tint, child: Icon(Icons.person_add_alt, color: p.accent)),
              title: Text(l.addNewPerson, style: t.titleSmall?.copyWith(color: p.accent)),
              onTap: () async {
                final contact = await showDialog<Contact>(context: context, builder: (_) => const _NewPersonDialog());
                if (contact != null && context.mounted) Navigator.pop(context, contact);
              },
            ),
            const Divider(),
            AsyncBody(
              value: contactsAsync,
              onRetry: () => ref.invalidate(contactsProvider),
              builder: (contacts) => contacts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.noContactsYet, style: t.bodyMedium?.copyWith(color: p.muted), textAlign: TextAlign.center),
                    )
                  : Column(
                      children: [
                        for (final c in contacts)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: p.chip,
                              child: Text(initials(c.name), style: t.labelLarge),
                            ),
                            title: Text(c.name),
                            subtitle: (c.phone ?? '').isEmpty ? null : Text(c.phone!),
                            onTap: () => Navigator.pop(context, c),
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

class _NewPersonDialog extends ConsumerStatefulWidget {
  const _NewPersonDialog();

  @override
  ConsumerState<_NewPersonDialog> createState() => _NewPersonDialogState();
}

class _NewPersonDialogState extends ConsumerState<_NewPersonDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _nameError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = l.errorNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _nameError = null;
      _formError = null;
    });
    try {
      final contact = await ref.read(repoProvider).createContact(name: _name.text, phone: _phone.text);
      ref.invalidate(contactsProvider);
      if (mounted) Navigator.pop(context, contact);
    } catch (_) {
      if (mounted) setState(() => _formError = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addNewPerson),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.personNameLabel, errorText: _nameError),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l.phoneOptionalLabel),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(_formError!, style: const TextStyle(color: LekkaColors.overdueText)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
