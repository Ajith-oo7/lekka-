import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// Every read and write for groups, contacts, loans and Records.
/// Row Level Security in the database decides what each person can see.
class LekkaRepo {
  LekkaRepo(this._client);

  final SupabaseClient _client;

  String get _me => _client.auth.currentUser!.id;

  // ---- Groups -------------------------------------------------------------

  Future<List<LoanGroup>> fetchGroups() async {
    final rows = await _client.from('groups').select('id, name, owner_id').order('name');
    return rows.map(LoanGroup.fromMap).toList();
  }

  Future<LoanGroup> createGroup(String name) async {
    final row = await _client
        .from('groups')
        .insert({'owner_id': _me, 'name': name.trim()})
        .select('id, name, owner_id')
        .single();
    return LoanGroup.fromMap(row);
  }

  // ---- Contacts -----------------------------------------------------------

  Future<List<Contact>> fetchContacts() async {
    final rows = await _client.from('contacts').select('id, name, phone').order('name');
    return rows.map(Contact.fromMap).toList();
  }

  Future<Contact> createContact({required String name, String? phone}) async {
    final cleanPhone = phone?.trim();
    final row = await _client
        .from('contacts')
        .insert({
          'owner_id': _me,
          'name': name.trim(),
          'phone': (cleanPhone == null || cleanPhone.isEmpty) ? null : cleanPhone,
        })
        .select('id, name, phone')
        .single();
    return Contact.fromMap(row);
  }

  // ---- Loans --------------------------------------------------------------

  static const _loanColumns = 'id, group_id, created_by, lender_user_id, borrower_user_id, '
      'contact_id, principal_paise, start_date, next_due_date, status, created_at, '
      'contacts(name), groups(name), loan_terms(*)';

  Future<List<Loan>> fetchLoans() async {
    final rows = await _client.from('loans').select(_loanColumns);
    return rows.map(Loan.fromMap).toList();
  }

  /// Outstanding balance per loan, from the loan_balances view.
  Future<Map<String, int>> fetchBalances() async {
    final rows = await _client.from('loan_balances').select('loan_id, outstanding_paise');
    return {
      for (final r in rows) r['loan_id'] as String: ((r['outstanding_paise'] as num?) ?? 0).toInt(),
    };
  }

  /// Creates the loan and terms version 1 together (create_loan in phase2_update.sql).
  /// Returns the new loan id.
  Future<String> createLoan({
    required String groupId,
    required String contactId,
    required int principalPaise,
    required DateTime startDate,
    required DateTime nextDueDate,
    required int rateBps,
    required RatePeriod ratePeriod,
    required InterestType interestType,
    required int lateRateBps,
    required int graceDays,
    bool iAmBorrower = false,
  }) async {
    final id = await _client.rpc('create_loan', params: {
      'p_group_id': groupId,
      'p_contact_id': contactId,
      'p_principal_paise': principalPaise,
      'p_start_date': toDbDate(startDate),
      'p_next_due_date': toDbDate(nextDueDate),
      'p_rate_bps': rateBps,
      'p_rate_period': ratePeriod.name,
      'p_interest_type': interestType.name,
      'p_late_rate_bps': lateRateBps,
      'p_grace_days': graceDays,
      'p_i_am_borrower': iAmBorrower,
    });
    return id as String;
  }

  /// Saves new terms as the next version. Older versions are never edited.
  /// The database adds a "Terms updated" record. The daily job uses the new
  /// terms from today (India time); earlier days keep the old ones.
  Future<void> changeTerms({
    required Loan loan,
    required int rateBps,
    required RatePeriod ratePeriod,
    required InterestType interestType,
    required int lateRateBps,
    required int graceDays,
  }) async {
    final next = (loan.currentTerms?.version ?? 0) + 1;
    await _client.from('loan_terms').insert({
      'loan_id': loan.id,
      'version': next,
      'rate_bps': rateBps,
      'rate_period': ratePeriod.name,
      'interest_type': interestType.name,
      'late_rate_bps': lateRateBps,
      'grace_days': graceDays,
      'created_by': _me,
    });
  }

  /// Marks a loan as closed. Closed loans stop getting interest and reminders.
  Future<void> closeLoan(String loanId) async {
    await _client.from('loans').update({'status': 'closed'}).eq('id', loanId);
  }

  // ---- Shared loans (Phase 4) ---------------------------------------------

  /// Names of the two sides of each visible loan: loan id → (lender, borrower).
  Future<Map<String, (String, String)>> fetchLoanPeople() async {
    final rows = await _client.rpc('loan_people') as List;
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        r['loan_id'] as String: ((r['lender_name'] as String?) ?? '', (r['borrower_name'] as String?) ?? ''),
    };
  }

  /// Invite code for the borrower of this loan (valid 7 days, single use).
  Future<String> createInvite(String loanId) async {
    return await _client.rpc('create_invite', params: {'p_loan_id': loanId}) as String;
  }

  /// Joins with an invite code. Returns the id of the loan that is now shared.
  Future<String> joinWithCode(String code) async {
    return await _client.rpc('join_with_code', params: {'p_code': code}) as String;
  }

  /// The borrower accepts a terms version.
  Future<void> acceptTerms(String termId) async {
    await _client.rpc('accept_terms', params: {'term_id': termId});
  }

  /// Ids of the payments the borrower has confirmed.
  Future<Set<String>> fetchConfirmedEntryIds() async {
    final rows = await _client.from('entry_confirmations').select('entry_id');
    return {for (final r in rows) r['entry_id'] as String};
  }

  /// The borrower confirms a payment the lender recorded.
  Future<void> confirmPayment(String entryId) async {
    await _client.from('entry_confirmations').insert({'entry_id': entryId, 'user_id': _me});
  }

  // ---- Reminders (Phase 5) ------------------------------------------------

  /// Reminders received, newest first (the latest 100).
  Future<List<AppNotification>> fetchNotifications() async {
    final rows = await _client
        .from('notifications')
        .select('id, loan_id, kind, created_at, to_lender, person_name, balance_paise, late_paise, due_date')
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map(AppNotification.fromMap).toList();
  }

  /// The lender nudges the borrower of a shared loan. The server allows at
  /// most 3 a day per loan and answers 429 after that (a FunctionException).
  Future<void> sendPing(String loanId) async {
    await _client.functions.invoke('send-reminders', body: {'ping_loan_id': loanId});
  }

  // ---- Problem reports (Phase 6) ------------------------------------------

  /// Sends a tester's note to the owner (read in the Supabase dashboard).
  Future<void> sendFeedback(String message, String appVersion) async {
    await _client.from('feedback').insert({
      'user_id': _me,
      'message': message.trim(),
      'app_version': appVersion,
    });
  }

  // ---- Records (ledger) ---------------------------------------------------

  /// Every Records entry the person can see, newest first.
  Future<List<LedgerEntry>> fetchEntries() async {
    final rows = await _client
        .from('ledger_entries')
        .select('id, loan_id, kind, amount_paise, entry_date, note, reverses_id, created_at');
    // Sorted here so the order never depends on how the server combines sorts.
    return rows.map(LedgerEntry.fromMap).toList()
      ..sort((a, b) {
        final byDate = b.entryDate.compareTo(a.entryDate);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
  }

  Future<void> recordPayment({
    required String loanId,
    required int amountPaise,
    required DateTime date,
    String? note,
  }) async {
    final cleanNote = note?.trim();
    await _client.from('ledger_entries').insert({
      'loan_id': loanId,
      'kind': EntryKind.payment.db,
      'amount_paise': amountPaise,
      'entry_date': toDbDate(date),
      'note': (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote,
      'created_by': _me,
    });
  }

  /// Corrects an entry by adding a reversal. The original is never changed.
  Future<void> reverseEntry(LedgerEntry original) async {
    await _client.from('ledger_entries').insert({
      'loan_id': original.loanId,
      'kind': EntryKind.reversal.db,
      'amount_paise': original.amountPaise,
      'entry_date': toDbDate(today()),
      'reverses_id': original.id,
      'created_by': _me,
    });
  }
}
