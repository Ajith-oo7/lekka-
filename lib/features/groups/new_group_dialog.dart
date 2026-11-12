import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Asks for a group name and creates the group. Returns it, or null if cancelled.
Future<LoanGroup?> showNewGroupDialog(BuildContext context) {
  return showDialog<LoanGroup>(context: context, builder: (_) => const _NewGroupDialog());
}

class _NewGroupDialog extends ConsumerStatefulWidget {
  const _NewGroupDialog();

  @override
  ConsumerState<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends ConsumerState<_NewGroupDialog> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = l.errorGroupNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await ref.read(repoProvider).createGroup(_name.text);
      ref.invalidate(groupsProvider);
      if (mounted) Navigator.pop(context, group);
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.newGroup),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _busy ? null : _save(),
        decoration: InputDecoration(labelText: l.groupNameLabel, errorText: _error),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
