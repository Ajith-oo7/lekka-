import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../l10n/app_localizations.dart';
import 'new_group_dialog.dart';

/// Groups: the named groups, with a "New group" button. Opening one lists its loans.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final groupsAsync = ref.watch(groupsProvider);
    final loans = ref.watch(loansProvider).valueOrNull ?? const <LoanView>[];

    return Scaffold(
      appBar: AppBar(title: Text(l.groupsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LekkaColors.primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.add),
        label: Text(l.newGroup),
        onPressed: () async {
          final group = await showNewGroupDialog(context);
          if (group != null && context.mounted) context.push(Routes.group(group.id));
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshLoanData(ref);
          await ref.read(groupsProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            AsyncBody(
              value: groupsAsync,
              onRetry: () => ref.invalidate(groupsProvider),
              builder: (groups) => groups.isEmpty
                  ? EmptyState(icon: Icons.folder_outlined, title: l.noGroupsTitle, body: l.noGroupsBody)
                  : Column(
                      children: [
                        for (final g in groups) ...[
                          LekkaCard(
                            padding: EdgeInsets.zero,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Icon(Icons.folder_outlined, color: p.accent),
                              title: Text(g.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                l.loanCount(loans.where((v) => v.loan.groupId == g.id).length),
                                style: t.bodySmall,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(Routes.group(g.id)),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
