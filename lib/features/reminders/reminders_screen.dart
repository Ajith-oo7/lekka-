import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/loan_providers.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';

/// Reminders: every notification the person received, newest first.
/// The text is built here in the app's language from the saved facts
/// (who, how much, late interest), the same way the push message is.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(notificationsProvider);
    final loanIds = {for (final v in ref.watch(loansProvider).valueOrNull ?? const <LoanView>[]) v.loan.id};

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(notificationsProvider);
        await ref.read(notificationsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(title: l.navReminders),
          const SizedBox(height: 6),
          AsyncBody(
            value: async,
            onRetry: () => ref.invalidate(notificationsProvider),
            builder: (list) => list.isEmpty
                ? EmptyState(icon: Icons.notifications_none, title: l.noRemindersTitle, body: l.noRemindersBody)
                : LekkaCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) const Divider(indent: 64),
                          _ReminderRow(
                            item: list[i],
                            onTap: list[i].loanId != null && loanIds.contains(list[i].loanId)
                                ? () => context.push(Routes.loan(list[i].loanId!))
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// (title, body) for a reminder, in the app's language.
(String, String) reminderText(AppLocalizations l, AppNotification n, String lang) {
  final name = n.personName.isEmpty ? l.appName : n.personName;
  final amount = formatRupees(n.balancePaise);
  final late = formatRupees(n.latePaise);
  final date = n.dueDate == null ? '' : formatDate(n.dueDate!, lang);
  return switch (n.kind) {
    'due_soon' => (
        l.remDueSoonTitle,
        n.toLender ? l.remDueSoonLender(name, date, amount) : l.remDueSoonBorrower(name, date, amount),
      ),
    'due_today' => (
        l.remDueTodayTitle,
        n.toLender ? l.remDueTodayLender(name, amount) : l.remDueTodayBorrower(name, amount),
      ),
    'overdue' => (
        l.remOverdueTitle,
        n.toLender ? l.remOverdueLender(name, late, amount) : l.remOverdueBorrower(name, late, amount),
      ),
    _ => (l.remPingTitle(name), l.remPingBody(name, amount)),
  };
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final p = LekkaPalette.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final (title, body) = reminderText(l, item, lang);

    final (IconData icon, Color color) = switch (item.kind) {
      'overdue' => (Icons.error_outline, LekkaColors.overdueText),
      'due_today' => (Icons.event_available_outlined, LekkaColors.dueSoonText),
      'due_soon' => (Icons.schedule, LekkaColors.dueSoonText),
      _ => (Icons.notifications_active_outlined, p.accent),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.chip, shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: t.bodyMedium?.copyWith(color: p.muted)),
                  const SizedBox(height: 4),
                  Text(formatDate(item.createdAt, lang), style: t.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
