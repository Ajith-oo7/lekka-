/// Plain data classes for the Phase 2 tables. Money is whole paise (int),
/// rates are basis points (1000 = 10.00%).
library;

DateTime _date(dynamic v) => DateTime.parse(v as String);
DateTime? _dateOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String);

/// A date as Postgres wants it: 2026-11-04.
String toDbDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's date with no time part.
DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class LoanGroup {
  const LoanGroup({required this.id, required this.name, required this.ownerId});

  final String id;
  final String name;
  final String ownerId;

  factory LoanGroup.fromMap(Map<String, dynamic> m) => LoanGroup(
        id: m['id'] as String,
        name: m['name'] as String,
        ownerId: m['owner_id'] as String,
      );
}

/// A person the lender tracks. They may never have the app.
class Contact {
  const Contact({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;

  factory Contact.fromMap(Map<String, dynamic> m) => Contact(
        id: m['id'] as String,
        name: m['name'] as String,
        phone: m['phone'] as String?,
      );
}

enum RatePeriod {
  day(1),
  week(7),
  month(30),
  year(365);

  const RatePeriod(this.days);

  /// Days in the period, as defined in the build prompt (section 8).
  final int days;

  static RatePeriod fromDb(String v) => RatePeriod.values.firstWhere((p) => p.name == v);
}

enum InterestType {
  simple,
  compound;

  static InterestType fromDb(String v) => InterestType.values.firstWhere((t) => t.name == v);
}

/// One version of a loan's terms. Versions are never edited; a change adds a new one.
class LoanTerms {
  const LoanTerms({
    required this.id,
    required this.loanId,
    required this.version,
    required this.rateBps,
    required this.ratePeriod,
    required this.interestType,
    required this.lateRateBps,
    required this.graceDays,
    required this.createdAt,
    this.acceptedAt,
  });

  final String id;
  final String loanId;
  final int version;
  final int rateBps;
  final RatePeriod ratePeriod;
  final InterestType interestType;
  final int lateRateBps;
  final int graceDays;
  final DateTime createdAt;

  /// When the borrower tapped Accept (shared loans). Null if not accepted.
  final DateTime? acceptedAt;

  factory LoanTerms.fromMap(Map<String, dynamic> m) => LoanTerms(
        id: m['id'] as String,
        loanId: m['loan_id'] as String,
        version: m['version'] as int,
        rateBps: m['rate_bps'] as int,
        ratePeriod: RatePeriod.fromDb(m['rate_period'] as String),
        interestType: InterestType.fromDb(m['interest_type'] as String),
        lateRateBps: m['late_rate_bps'] as int,
        graceDays: m['grace_days'] as int,
        createdAt: _date(m['created_at']),
        acceptedAt: _dateOrNull(m['accepted_at']),
      );
}

class Loan {
  const Loan({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.createdBy,
    required this.lenderUserId,
    required this.borrowerUserId,
    required this.contactId,
    required this.contactName,
    required this.principalPaise,
    required this.startDate,
    required this.nextDueDate,
    required this.status,
    required this.terms,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String createdBy;
  final String? lenderUserId;
  final String? borrowerUserId;
  final String? contactId;
  final String contactName;
  final int principalPaise;
  final DateTime startDate;
  final DateTime? nextDueDate;
  final String status; // 'active' or 'closed'
  final List<LoanTerms> terms; // all versions, oldest first

  /// The person who controls the terms (same rule as can_write_loan in the database).
  String get lenderId => lenderUserId ?? createdBy;

  bool get isActive => status == 'active';

  /// Both sides have the app on this loan.
  bool get isShared => lenderUserId != null && borrowerUserId != null;

  /// The borrower has accepted some version of the terms.
  bool get termsAccepted => terms.any((t) => t.acceptedAt != null);

  /// The newest terms version, or null if none was saved.
  LoanTerms? get currentTerms => terms.isEmpty ? null : terms.last;

  LoanTerms? termsVersion(int version) {
    for (final t in terms) {
      if (t.version == version) return t;
    }
    return null;
  }

  factory Loan.fromMap(Map<String, dynamic> m) {
    final terms = ((m['loan_terms'] as List?) ?? const [])
        .map((e) => LoanTerms.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.version.compareTo(b.version));
    return Loan(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      groupName: (m['groups'] as Map?)?['name'] as String? ?? '',
      createdBy: m['created_by'] as String,
      lenderUserId: m['lender_user_id'] as String?,
      borrowerUserId: m['borrower_user_id'] as String?,
      contactId: m['contact_id'] as String?,
      contactName: (m['contacts'] as Map?)?['name'] as String? ?? '',
      principalPaise: (m['principal_paise'] as num).toInt(),
      startDate: _date(m['start_date']),
      nextDueDate: _dateOrNull(m['next_due_date']),
      status: m['status'] as String,
      terms: terms,
    );
  }
}

enum EntryKind {
  loanCreated('loan_created'),
  payment('payment'),
  interestAccrual('interest_accrual'),
  lateInterest('late_interest'),
  termsChange('terms_change'),
  reversal('reversal');

  const EntryKind(this.db);

  final String db;

  static EntryKind fromDb(String v) => EntryKind.values.firstWhere((k) => k.db == v);

  /// +1 adds to the balance, -1 lowers it, 0 does not change it.
  /// Same as kind_sign() in the database.
  int get sign => switch (this) {
        EntryKind.loanCreated || EntryKind.interestAccrual || EntryKind.lateInterest => 1,
        EntryKind.payment => -1,
        _ => 0,
      };
}

/// One row of Records. Rows are never edited or deleted.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.loanId,
    required this.kind,
    required this.amountPaise,
    required this.entryDate,
    required this.note,
    required this.reversesId,
    required this.createdAt,
  });

  final String id;
  final String loanId;
  final EntryKind kind;
  final int amountPaise;
  final DateTime entryDate;
  final String? note;
  final String? reversesId;
  final DateTime createdAt;

  factory LedgerEntry.fromMap(Map<String, dynamic> m) => LedgerEntry(
        id: m['id'] as String,
        loanId: m['loan_id'] as String,
        kind: EntryKind.fromDb(m['kind'] as String),
        amountPaise: (m['amount_paise'] as num).toInt(),
        entryDate: _date(m['entry_date']),
        note: m['note'] as String?,
        reversesId: m['reverses_id'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

/// A reminder the person received (Reminders screen).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.loanId,
    required this.kind,
    required this.createdAt,
    required this.toLender,
    required this.personName,
    required this.balancePaise,
    required this.latePaise,
    required this.dueDate,
  });

  final String id;
  final String? loanId;
  final String kind; // 'due_soon', 'due_today', 'overdue' or 'ping'
  final DateTime createdAt;

  /// True when it was sent to a lender whose borrower has no app.
  final bool toLender;
  final String personName;
  final int balancePaise;
  final int latePaise;
  final DateTime? dueDate;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        loanId: m['loan_id'] as String?,
        kind: m['kind'] as String,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        toLender: (m['to_lender'] as bool?) ?? false,
        personName: (m['person_name'] as String?) ?? '',
        balancePaise: ((m['balance_paise'] as num?) ?? 0).toInt(),
        latePaise: ((m['late_paise'] as num?) ?? 0).toInt(),
        dueDate: _dateOrNull(m['due_date']),
      );
}
