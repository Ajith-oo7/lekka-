import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/loan_math.dart';
import 'models.dart';
import 'providers.dart';
import 'repo.dart';

final repoProvider = Provider<LekkaRepo>((ref) => LekkaRepo(Supabase.instance.client));

final groupsProvider = FutureProvider<List<LoanGroup>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const [];
  return ref.read(repoProvider).fetchGroups();
});

final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const [];
  return ref.read(repoProvider).fetchContacts();
});

/// Every Records entry the person can see, newest first.
final entriesProvider = FutureProvider<List<LedgerEntry>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const [];
  return ref.read(repoProvider).fetchEntries();
});

/// Ids of payments the borrower has confirmed (shared loans).
final confirmationsProvider = FutureProvider<Set<String>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const {};
  return ref.read(repoProvider).fetchConfirmedEntryIds();
});

/// Reminders received, newest first.
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  if (ref.watch(currentUserProvider) == null) return const [];
  return ref.read(repoProvider).fetchNotifications();
});

/// A loan plus what the screens need: balance, whose side it is on, status.
class LoanView {
  const LoanView({
    required this.loan,
    required this.outstandingPaise,
    required this.iAmBorrower,
    required this.canWrite,
    required this.otherName,
    required this.status,
  });

  final Loan loan;
  final int outstandingPaise;

  /// True when the signed-in person took this loan (Money Borrowed side).
  final bool iAmBorrower;

  /// True when the signed-in person keeps this loan's record: the lender, or
  /// the borrower of a loan whose lender is not on the app. Same rule as
  /// can_write_loan in the database.
  final bool canWrite;

  /// The other person's name: the borrower for a lender, the lender for a borrower.
  final String otherName;
  final LoanStatus status;

  /// Money Lent side.
  bool get isLender => !iAmBorrower;
}

/// All loans the person can see, sorted by due date (no date last).
final loansProvider = FutureProvider<List<LoanView>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final repo = ref.read(repoProvider);
  final (loans, balances, people) =
      await (repo.fetchLoans(), repo.fetchBalances(), repo.fetchLoanPeople()).wait;

  final views = <LoanView>[];
  for (final loan in loans) {
    final iAmBorrower = loan.borrowerUserId == user.id;
    final (lenderName, borrowerName) = people[loan.id] ?? ('', '');
    final other = iAmBorrower ? lenderName : borrowerName;
    final outstanding = balances[loan.id] ?? loan.principalPaise;
    views.add(LoanView(
      loan: loan,
      outstandingPaise: outstanding,
      iAmBorrower: iAmBorrower,
      canWrite: loan.lenderId == user.id,
      otherName: other.isNotEmpty ? other : loan.contactName,
      status: loanStatus(nextDueDate: loan.nextDueDate, outstandingPaise: outstanding),
    ));
  }
  views.sort((a, b) {
    final da = a.loan.nextDueDate, db = b.loan.nextDueDate;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return views;
});

/// One loan by id, from the loaded list.
final loanViewProvider = Provider.family<AsyncValue<LoanView?>, String>((ref, id) {
  return ref.watch(loansProvider).whenData((list) {
    for (final v in list) {
      if (v.loan.id == id) return v;
    }
    return null;
  });
});

/// Call after any change so every screen shows fresh numbers.
void refreshLoanData(WidgetRef ref) {
  ref.invalidate(loansProvider);
  ref.invalidate(entriesProvider);
  ref.invalidate(confirmationsProvider);
  ref.invalidate(groupsProvider);
  ref.invalidate(contactsProvider);
}

/// Keeps two phones in step: when a loan, its terms, Records or a
/// confirmation changes in the database, reload. Changes are grouped for
/// half a second so the daily interest job causes one reload, not hundreds.
/// Row Level Security also applies to these change messages.
final realtimeSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(currentUserProvider.select((u) => u?.id));
  if (userId == null) return;

  final client = Supabase.instance.client;
  Timer? timer;
  void changed(PostgresChangePayload payload) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), () {
      ref.invalidate(loansProvider);
      ref.invalidate(entriesProvider);
      ref.invalidate(confirmationsProvider);
      ref.invalidate(notificationsProvider);
    });
  }

  final channel = client.channel('lekka-loan-changes');
  for (final table in const ['loans', 'loan_terms', 'ledger_entries', 'entry_confirmations', 'notifications']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: changed,
    );
  }
  channel.subscribe();

  ref.onDispose(() {
    timer?.cancel();
    client.removeChannel(channel);
  });
});
